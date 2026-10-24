import hashlib
import json
import uuid
from decimal import Decimal
from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework.exceptions import PermissionDenied, ValidationError
from config.errors import Conflict
from .models import (
    Account,
    AuditEvent,
    Company,
    IdempotencyRecord,
    JournalTransaction,
    LedgerEntry,
    Membership,
    Payment,
)

WRITERS = ("OWNER", "ACCOUNTANT")


def membership(user, company_id, roles=None, lock=False):
    qs = Membership.objects
    if lock:
        qs = qs.select_for_update()
    member = get_object_or_404(qs, company_id=company_id, user=user, is_active=True)
    if roles and member.role not in roles:
        raise PermissionDenied("Недостаточно прав")
    return member


def accessible_account(user, account_id):
    account = get_object_or_404(Account, pk=account_id, is_system=False)
    membership(user, account.company_id)
    return account


def accessible_payment(user, payment_id):
    payment = get_object_or_404(
        Payment.objects.select_related("source", "destination__company"), pk=payment_id
    )
    membership(user, payment.source.company_id)
    return payment


def audit(user, company_id, action, entity, request_id="", **changes):
    AuditEvent.objects.create(
        actor=user,
        company_id=company_id,
        action=action,
        entity_id=entity.pk,
        request_id=request_id,
        changes=changes,
    )


@transaction.atomic
def create_company(user, name):
    company = Company.objects.create(name=name, owner=user)
    Membership.objects.create(company=company, user=user, role="OWNER")
    audit(user, company.pk, "company.created", company)
    return company


@transaction.atomic
def add_member(user, company_id, target, role, request_id=""):
    membership(user, company_id, ("OWNER",), lock=True)
    if role not in ("ACCOUNTANT", "VIEWER"):
        raise ValidationError({"role": "Допустимы ACCOUNTANT и VIEWER"})
    member, created = Membership.objects.get_or_create(
        company_id=company_id, user=target, defaults={"role": role}
    )
    if not created:
        raise Conflict("member_exists", "Участник уже добавлен; используйте PATCH")
    audit(user, company_id, "member.added", member, request_id, role=role)
    return member


@transaction.atomic
def change_member(user, company_id, member_id, data, request_id=""):
    membership(user, company_id, ("OWNER",), lock=True)
    member = get_object_or_404(Membership.objects.select_for_update(), pk=member_id, company_id=company_id)
    if member.role == "OWNER":
        raise PermissionDenied("Владельца нельзя изменить")
    for key, value in data.items():
        setattr(member, key, value)
    member.save(update_fields=list(data))
    audit(user, company_id, "member.changed", member, request_id, **data)
    return member


@transaction.atomic
def create_account(user, company_id, name, request_id=""):
    membership(user, company_id, ("OWNER",), lock=True)
    account = Account.objects.create(
        company_id=company_id, name=name, number="DEMO-" + uuid.uuid4().hex.upper()
    )
    audit(user, company_id, "account.opened", account, request_id)
    return account


@transaction.atomic
def close_account(user, account_id, request_id=""):
    account = accessible_account(user, account_id)
    membership(user, account.company_id, ("OWNER",), lock=True)
    account = Account.objects.select_for_update().get(pk=account_id)
    pending = Payment.objects.filter(Q(source=account) | Q(destination=account), status="PENDING_APPROVAL")
    if account.cached_balance or pending.exists():
        raise Conflict("account_not_empty", "На счёте есть средства или ожидающие платежи")
    if account.status != "CLOSED":
        account.status, account.closed_at = "CLOSED", timezone.now()
        account.save(update_fields=["status", "closed_at"])
        audit(user, account.company_id, "account.closed", account, request_id)
    return account


def lock_accounts(*ids):
    return {a.pk: a for a in Account.objects.select_for_update().filter(pk__in=ids).order_by("pk")}


def check_accounts(source, destination):
    if source.pk == destination.pk or source.is_system or destination.is_system:
        raise ValidationError({"destination": "Нужны два разных клиентских счёта"})
    if source.status != "ACTIVE" or destination.status != "ACTIVE":
        raise Conflict("account_closed", "Счёт закрыт")


def payment_data(payment):
    return {
        "id": str(payment.id),
        "source": str(payment.source_id),
        "destination": str(payment.destination_id),
        "source_number": payment.source.number,
        "destination_number": payment.destination.number,
        "destination_name": payment.destination.company.name,
        "amount": str(payment.amount),
        "purpose": payment.purpose,
        "status": payment.status,
        "author": str(payment.author_id),
        "approver": str(payment.approver_id) if payment.approver_id else None,
        "reason": payment.reason,
        "created_at": payment.created_at.isoformat(),
        "executed_at": payment.executed_at.isoformat() if payment.executed_at else None,
    }


@transaction.atomic
def idempotent(user, action, key, data, operation, status=200):
    if not key or len(key) > 128:
        raise ValidationError({"Idempotency-Key": "Обязателен ключ длиной 1–128 символов"})
    digest = hashlib.sha256(
        json.dumps(data, sort_keys=True, default=str, separators=(",", ":")).encode()
    ).hexdigest()
    rec, _ = IdempotencyRecord.objects.get_or_create(
        user=user, action=action, key=key, defaults={"request_hash": digest, "status_code": status}
    )
    rec = IdempotencyRecord.objects.select_for_update().get(pk=rec.pk)
    if rec.request_hash != digest:
        raise Conflict("idempotency_conflict", "Ключ использован с другими данными")
    if rec.response is not None:
        return rec.response, rec.status_code
    result = operation()
    rec.response, rec.status_code = result, status
    rec.save(update_fields=["response", "status_code"])
    return result, status


@transaction.atomic
def create_payment(user, company_id, data, key, request_id=""):
    membership(user, company_id, WRITERS, lock=True)

    def operation():
        source = get_object_or_404(Account, pk=data["source"], company_id=company_id, is_system=False)
        dest = get_object_or_404(Account, pk=data["destination"], is_system=False)
        locked = lock_accounts(source.pk, dest.pk)
        check_accounts(locked[source.pk], locked[dest.pk])
        pay = Payment.objects.create(
            source=source, destination=dest, amount=data["amount"], purpose=data["purpose"], author=user
        )
        audit(user, company_id, "payment.created", pay, request_id)
        return payment_data(pay)

    return idempotent(user, f"create:{company_id}", key, data, operation, 201)


@transaction.atomic
def edit_payment(user, payment_id, data, request_id=""):
    initial = accessible_payment(user, payment_id)
    membership(user, initial.source.company_id, WRITERS, lock=True)
    pay = Payment.objects.select_for_update().get(pk=payment_id)
    if pay.author_id != user.pk:
        raise PermissionDenied("Изменять может только автор")
    if pay.status != "DRAFT":
        raise Conflict("invalid_state", "Можно изменить только черновик")
    source_id = data.get("source", pay.source_id)
    dest_id = data.get("destination", pay.destination_id)
    get_object_or_404(Account, pk=source_id, company_id=initial.source.company_id, is_system=False)
    get_object_or_404(Account, pk=dest_id, is_system=False)
    locked = lock_accounts(source_id, dest_id)
    check_accounts(locked[source_id], locked[dest_id])
    pay.source_id, pay.destination_id = source_id, dest_id
    pay.amount, pay.purpose = data.get("amount", pay.amount), data.get("purpose", pay.purpose)
    pay.save(update_fields=["source", "destination", "amount", "purpose"])
    audit(user, initial.source.company_id, "payment.edited", pay, request_id)
    return pay


def write_entries(journal, source, destination, amount):
    LedgerEntry.objects.create(journal=journal, account=source, side="DEBIT", amount=amount)
    LedgerEntry.objects.create(journal=journal, account=destination, side="CREDIT", amount=amount)


@transaction.atomic
def act_payment(user, payment_id, action, key, data=None, request_id=""):
    data = data or {}
    initial = accessible_payment(user, payment_id)
    member = membership(
        user, initial.source.company_id, ("OWNER",) if action in ("approve", "reject") else WRITERS, lock=True
    )

    def operation():
        pay = Payment.objects.select_for_update().get(pk=payment_id)
        if action == "approve" and pay.status == "EXECUTED":
            return payment_data(pay)
        if action in ("submit", "cancel") and member.role != "OWNER" and pay.author_id != user.pk:
            raise PermissionDenied("Действие доступно автору или владельцу")
        if action == "submit":
            if pay.author_id != user.pk:
                raise PermissionDenied("Отправляет только автор")
            if pay.status != "DRAFT":
                raise Conflict("invalid_state", "Платёж не является черновиком")
            accounts = lock_accounts(pay.source_id, pay.destination_id)
            check_accounts(accounts[pay.source_id], accounts[pay.destination_id])
            pay.status = "PENDING_APPROVAL"
        elif action in ("approve", "reject"):
            if pay.status != "PENDING_APPROVAL":
                raise Conflict("invalid_state", "Платёж не ожидает согласования")
            if action == "reject":
                pay.reason = data["reason"]
                pay.status = "REJECTED"
            else:
                accounts = lock_accounts(pay.source_id, pay.destination_id)
                source, dest = accounts[pay.source_id], accounts[pay.destination_id]
                check_accounts(source, dest)
                if source.cached_balance < pay.amount:
                    raise Conflict("insufficient_funds", "Недостаточно средств")
                journal = JournalTransaction.objects.create(payment=pay, kind="TRANSFER")
                write_entries(journal, source, dest, pay.amount)
                source.cached_balance -= pay.amount
                dest.cached_balance += pay.amount
                source.save(update_fields=["cached_balance"])
                dest.save(update_fields=["cached_balance"])
                pay.status, pay.approver, pay.executed_at = "EXECUTED", user, timezone.now()
        elif action == "cancel":
            if pay.status not in ("DRAFT", "PENDING_APPROVAL"):
                raise Conflict("invalid_state", "Нельзя отменить завершённый платёж")
            pay.status = "CANCELLED"
        else:
            raise ValidationError({"action": "Неизвестное действие"})
        pay.save(update_fields=["status", "reason", "approver", "executed_at"])
        audit(user, initial.source.company_id, f"payment.{action}", pay, request_id, status=pay.status)
        return payment_data(pay)

    return idempotent(user, f"{action}:{payment_id}", key, data, operation)


@transaction.atomic
def fund_demo(account_id, amount, key, actor=None):
    system, _ = Account.objects.get_or_create(
        number="SYSTEM-DEMO", defaults={"name": "Demo funding asset", "is_system": True}
    )
    accounts = lock_accounts(system.pk, account_id)
    account, system = accounts[account_id], accounts[system.pk]
    existing = JournalTransaction.objects.filter(funding_key=key).first()
    if existing:
        return existing
    if account.is_system or account.status != "ACTIVE" or amount <= 0:
        raise ValidationError("Недопустимое пополнение")
    journal = JournalTransaction.objects.create(kind="FUNDING", funding_key=key)
    write_entries(journal, system, account, amount)
    system.cached_balance += amount
    account.cached_balance += amount
    system.save(update_fields=["cached_balance"])
    account.save(update_fields=["cached_balance"])
    audit(actor, account.company_id, "demo.funded", journal, amount=str(amount))
    return journal


def reconcile():
    from django.db import connection

    # A single repeatable-read snapshot avoids false mismatches during live transfers.
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        errors = []
        for account in Account.objects.all():
            credits = sum(account.entries.filter(side="CREDIT").values_list("amount", flat=True), Decimal(0))
            debits = sum(account.entries.filter(side="DEBIT").values_list("amount", flat=True), Decimal(0))
            balance = debits - credits if account.is_system else credits - debits
            if balance != account.cached_balance or balance < 0:
                errors.append(f"account:{account.id}")
        for journal in JournalTransaction.objects.prefetch_related("entries"):
            entries = list(journal.entries.all())
            value = sum((e.amount if e.side == "DEBIT" else -e.amount for e in entries), Decimal(0))
            if len(entries) < 2 or value != 0:
                errors.append(f"journal:{journal.id}")
        return errors
