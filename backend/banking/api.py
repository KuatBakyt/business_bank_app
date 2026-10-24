from django.contrib.auth import get_user_model
from django.core.files.storage import default_storage
from django.db import transaction
from django.http import FileResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from drf_spectacular.utils import extend_schema, OpenApiParameter, OpenApiTypes
from rest_framework import generics
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from config.throttling import RecipientThrottle
from . import services
from .models import Account, AuditEvent, Company, LedgerEntry, Membership, Payment, StatementExport
from .serializers import (
    AccountInput,
    AccountSerializer,
    AuditSerializer,
    CompanyInput,
    CompanySerializer,
    EmptyInput,
    EntrySerializer,
    MemberInput,
    MemberPatch,
    MemberSerializer,
    PaymentInput,
    PaymentSerializer,
    ReasonInput,
    RecipientInput,
    RecipientOutput,
    StatementInput,
    StatementSerializer,
)

IDEMPOTENCY = OpenApiParameter(
    "Idempotency-Key",
    OpenApiTypes.STR,
    OpenApiParameter.HEADER,
    required=True,
    description="Уникальный ключ повтора длиной до 128 символов",
)


def parsed(cls, request, partial=False):
    serializer = cls(data=request.data, partial=partial)
    serializer.is_valid(raise_exception=True)
    return serializer.validated_data


class CompanyList(generics.ListCreateAPIView):
    serializer_class = CompanySerializer

    def get_queryset(self):
        return Company.objects.filter(membership__user=self.request.user, membership__is_active=True)

    @extend_schema(request=CompanyInput, responses={201: CompanySerializer})
    def post(self, request):
        company = services.create_company(request.user, **parsed(CompanyInput, request))
        return Response(CompanySerializer(company).data, status=201)


class MemberList(generics.ListCreateAPIView):
    serializer_class = MemberSerializer

    def get_queryset(self):
        services.membership(self.request.user, self.kwargs["company_id"])
        return Membership.objects.filter(company_id=self.kwargs["company_id"]).select_related("user")

    @extend_schema(request=MemberInput, responses={201: MemberSerializer})
    def post(self, request, company_id):
        data = parsed(MemberInput, request)
        services.membership(request.user, company_id, ("OWNER",))
        target = get_object_or_404(get_user_model(), email__iexact=data["email"], is_active=True)
        member = services.add_member(request.user, company_id, target, data["role"], request.request_id)
        return Response(MemberSerializer(member).data, status=201)


class MemberDetail(APIView):
    @extend_schema(request=MemberPatch, responses=MemberSerializer)
    def patch(self, request, company_id, member_id):
        data = parsed(MemberPatch, request)
        if not data:
            raise ValidationError("Передайте роль или is_active")
        member = services.change_member(request.user, company_id, member_id, data, request.request_id)
        return Response(MemberSerializer(member).data)


class AccountList(generics.ListCreateAPIView):
    serializer_class = AccountSerializer

    def get_queryset(self):
        services.membership(self.request.user, self.kwargs["company_id"])
        return Account.objects.filter(company_id=self.kwargs["company_id"], is_system=False)

    @extend_schema(request=AccountInput, responses={201: AccountSerializer})
    def post(self, request, company_id):
        account = services.create_account(
            request.user, company_id, **parsed(AccountInput, request), request_id=request.request_id
        )
        return Response(AccountSerializer(account).data, status=201)


class AccountClose(APIView):
    @extend_schema(request=EmptyInput, responses=AccountSerializer)
    def post(self, request, account_id):
        parsed(EmptyInput, request)
        account = services.close_account(request.user, account_id, request.request_id)
        return Response(AccountSerializer(account).data)


class RecipientResolve(APIView):
    throttle_classes = [RecipientThrottle]

    @extend_schema(request=RecipientInput, responses=RecipientOutput)
    def post(self, request):
        if not Membership.objects.filter(user=request.user, is_active=True).exists():
            from rest_framework.exceptions import PermissionDenied

            raise PermissionDenied("Нет активной компании")
        account = get_object_or_404(
            Account.objects.select_related("company"),
            number=parsed(RecipientInput, request)["number"],
            is_system=False,
            status="ACTIVE",
        )
        return Response(
            {"id": str(account.pk), "number": account.number, "company_name": account.company.name}
        )


class PaymentList(generics.ListCreateAPIView):
    serializer_class = PaymentSerializer

    def get_queryset(self):
        services.membership(self.request.user, self.kwargs["company_id"])
        qs = Payment.objects.filter(source__company_id=self.kwargs["company_id"])
        state = self.request.query_params.get("status")
        if state:
            if state not in Payment.Status.values:
                raise ValidationError({"status": "Неизвестный статус"})
            qs = qs.filter(status=state)
        return qs.order_by("-created_at", "-id")

    @extend_schema(request=PaymentInput, responses={201: PaymentSerializer}, parameters=[IDEMPOTENCY])
    def post(self, request, company_id):
        data, code = services.create_payment(
            request.user,
            company_id,
            parsed(PaymentInput, request),
            request.headers.get("Idempotency-Key"),
            request.request_id,
        )
        return Response(data, status=code)


class PaymentDetail(generics.RetrieveUpdateAPIView):
    serializer_class = PaymentSerializer
    http_method_names = ["get", "patch", "head", "options"]

    def get_object(self):
        return services.accessible_payment(self.request.user, self.kwargs["payment_id"])

    @extend_schema(request=PaymentInput, responses=PaymentSerializer, parameters=[IDEMPOTENCY])
    def patch(self, request, payment_id):
        body = parsed(PaymentInput, request, partial=True)
        with transaction.atomic():
            pay = services.accessible_payment(request.user, payment_id)
            services.membership(request.user, pay.source.company_id, services.WRITERS, lock=True)
            if pay.author_id != request.user.pk:
                from rest_framework.exceptions import PermissionDenied

                raise PermissionDenied("Изменять может только автор")
            result, code = services.idempotent(
                request.user,
                f"edit:{payment_id}",
                request.headers.get("Idempotency-Key"),
                body,
                lambda: services.payment_data(
                    services.edit_payment(request.user, payment_id, body, request.request_id)
                ),
            )
        return Response(result, status=code)


class PaymentAction(APIView):
    action = None

    @extend_schema(request=EmptyInput, responses=PaymentSerializer, parameters=[IDEMPOTENCY])
    def post(self, request, payment_id):
        body = parsed(EmptyInput, request)
        result, code = services.act_payment(
            request.user,
            payment_id,
            self.action,
            request.headers.get("Idempotency-Key"),
            body,
            request.request_id,
        )
        return Response(result, status=code)


class Submit(PaymentAction):
    action = "submit"


class Approve(PaymentAction):
    action = "approve"


class Cancel(PaymentAction):
    action = "cancel"


class Reject(PaymentAction):
    action = "reject"

    @extend_schema(request=ReasonInput, responses=PaymentSerializer, parameters=[IDEMPOTENCY])
    def post(self, request, payment_id):
        result, code = services.act_payment(
            request.user,
            payment_id,
            self.action,
            request.headers.get("Idempotency-Key"),
            parsed(ReasonInput, request),
            request.request_id,
        )
        return Response(result, status=code)


class EntryList(generics.ListAPIView):
    serializer_class = EntrySerializer

    def get_queryset(self):
        account = services.accessible_account(self.request.user, self.kwargs["account_id"])
        qs = (
            LedgerEntry.objects.filter(account=account)
            .select_related("journal__payment")
            .order_by("-journal__posted_at", "-id")
        )
        if "date_from" in self.request.query_params or "date_to" in self.request.query_params:
            from .statements import boundaries
            from datetime import date

            try:
                start = date.fromisoformat(self.request.query_params["date_from"])
                end = date.fromisoformat(self.request.query_params["date_to"])
            except (KeyError, ValueError):
                raise ValidationError("Нужны date_from и date_to в формате YYYY-MM-DD") from None
            if end < start:
                raise ValidationError("Неверный период")
            lo, hi = boundaries(start, end)
            qs = qs.filter(journal__posted_at__gte=lo, journal__posted_at__lt=hi)
        return qs


class AuditList(generics.ListAPIView):
    serializer_class = AuditSerializer

    def get_queryset(self):
        services.membership(self.request.user, self.kwargs["company_id"], ("OWNER",))
        return AuditEvent.objects.filter(company_id=self.kwargs["company_id"]).order_by("-created_at", "-id")


class StatementCreate(APIView):
    @extend_schema(request=StatementInput, responses={202: StatementSerializer})
    def post(self, request, account_id):
        account = services.accessible_account(request.user, account_id)
        data = parsed(StatementInput, request)
        export = StatementExport.objects.create(account=account, requested_by=request.user, **data)
        # Beat reliably dispatches QUEUED rows even if the broker is unavailable here.
        return Response(StatementSerializer(export).data, status=202)


class StatementDetail(generics.RetrieveAPIView):
    serializer_class = StatementSerializer

    def get_object(self):
        export = get_object_or_404(StatementExport, pk=self.kwargs["export_id"])
        services.accessible_account(self.request.user, export.account_id)
        return export


class StatementDownload(APIView):
    @extend_schema(responses={(200, "application/octet-stream"): OpenApiTypes.BINARY})
    def get(self, request, export_id):
        from config.errors import Conflict

        with transaction.atomic():
            export = get_object_or_404(StatementExport.objects.select_for_update(), pk=export_id)
            services.accessible_account(request.user, export.account_id)
            if export.status != "READY" or export.expires_at <= timezone.now():
                raise Conflict("export_unavailable", "Выписка не готова или истекла")
            if not export.private_file or not default_storage.exists(export.private_file.name):
                raise Conflict("export_unavailable", "Файл недоступен")
            handle = export.private_file.open("rb")
        response = FileResponse(handle, as_attachment=True, filename=f"statement-{export.pk}.{export.format}")
        response["Cache-Control"] = "no-store"
        return response
