from decimal import Decimal
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from .models import Account, AuditEvent, Company, LedgerEntry, Membership, Payment, StatementExport


class StrictSerializer(serializers.Serializer):
    def to_internal_value(self, data):
        unknown = set(data) - set(self.fields)
        if unknown:
            raise serializers.ValidationError({key: "Неизвестное поле" for key in unknown})
        return super().to_internal_value(data)


class RegisterSerializer(StrictSerializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=8, max_length=128)
    first_name = serializers.CharField(max_length=150, required=False, default="")

    def validate(self, data):
        User = get_user_model()
        data["email"] = data["email"].strip().lower()
        if User.objects.filter(email__iexact=data["email"]).exists():
            raise serializers.ValidationError({"email": "Email уже зарегистрирован"})
        validate_password(data["password"], User(email=data["email"], first_name=data["first_name"]))
        return data


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = get_user_model()
        fields = ["id", "email", "first_name"]


class CompanyInput(StrictSerializer):
    name = serializers.CharField(max_length=200)


class CompanySerializer(serializers.ModelSerializer):
    class Meta:
        model = Company
        fields = ["id", "name", "owner", "created_at"]


class MemberInput(StrictSerializer):
    email = serializers.EmailField()
    role = serializers.ChoiceField(choices=["ACCOUNTANT", "VIEWER"])


class MemberPatch(StrictSerializer):
    role = serializers.ChoiceField(choices=["ACCOUNTANT", "VIEWER"], required=False)
    is_active = serializers.BooleanField(required=False)


class MemberSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(source="user.email")

    class Meta:
        model = Membership
        fields = ["id", "user", "email", "role", "is_active"]


class AccountInput(StrictSerializer):
    name = serializers.CharField(max_length=100)


class AccountSerializer(serializers.ModelSerializer):
    class Meta:
        model = Account
        fields = [
            "id",
            "company",
            "number",
            "name",
            "currency",
            "status",
            "cached_balance",
            "created_at",
            "closed_at",
        ]


class PaymentInput(StrictSerializer):
    source = serializers.UUIDField()
    destination = serializers.UUIDField()
    amount = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0.01"), max_value=Decimal("100000000.00")
    )
    purpose = serializers.CharField(max_length=500, allow_blank=False)


class PaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Payment
        fields = [
            "id",
            "source",
            "destination",
            "amount",
            "purpose",
            "status",
            "author",
            "approver",
            "reason",
            "created_at",
            "executed_at",
        ]


class ReasonInput(StrictSerializer):
    reason = serializers.CharField(max_length=500)


class EmptyInput(StrictSerializer):
    pass


class RecipientInput(StrictSerializer):
    number = serializers.CharField(max_length=45)


class RecipientOutput(serializers.Serializer):
    id = serializers.UUIDField()
    number = serializers.CharField()
    company_name = serializers.CharField()


class EntrySerializer(serializers.ModelSerializer):
    posted_at = serializers.DateTimeField(source="journal.posted_at")
    operation_id = serializers.UUIDField(source="journal.id")
    purpose = serializers.SerializerMethodField()

    def get_purpose(self, obj) -> str:
        return obj.journal.payment.purpose if obj.journal.payment_id else "Тестовое пополнение"

    class Meta:
        model = LedgerEntry
        fields = ["id", "operation_id", "posted_at", "side", "amount", "purpose"]


class AuditSerializer(serializers.ModelSerializer):
    class Meta:
        model = AuditEvent
        fields = ["id", "actor", "action", "entity_id", "created_at", "request_id", "changes"]


class StatementInput(StrictSerializer):
    date_from = serializers.DateField()
    date_to = serializers.DateField()
    format = serializers.ChoiceField(choices=["csv", "pdf"])

    def validate(self, data):
        if data["date_to"] < data["date_from"] or (data["date_to"] - data["date_from"]).days >= 366:
            raise serializers.ValidationError("Период от 1 до 366 дней")
        return data


class StatementSerializer(serializers.ModelSerializer):
    class Meta:
        model = StatementExport
        fields = [
            "id",
            "account",
            "date_from",
            "date_to",
            "format",
            "status",
            "error_code",
            "created_at",
            "expires_at",
        ]
