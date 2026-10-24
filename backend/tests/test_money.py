from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from threading import Barrier
from unittest.mock import patch
import uuid
import pytest
from django.db import transaction, IntegrityError, close_old_connections
from banking import services
from banking.models import Account, Payment, JournalTransaction, LedgerEntry, AuditEvent
from config.errors import Conflict

pytestmark = pytest.mark.django_db(transaction=True)


def draft(d, amount="20.00", reverse=False, author=None):
    user = author or d["owner"]
    source, destination = d["source"], d["destination"]
    company = d["company"]
    if reverse:
        source, destination, company, user = destination, source, d["partner"], d["other"]
    payload, _ = services.create_payment(
        user,
        company.pk,
        {
            "source": source.pk,
            "destination": destination.pk,
            "amount": Decimal(amount),
            "purpose": "Services",
        },
        str(uuid.uuid4()),
    )
    return Payment.objects.get(pk=payload["id"])


def pending(d, **kwargs):
    pay = draft(d, **kwargs)
    user = d["other"] if kwargs.get("reverse") else kwargs.get("author") or d["owner"]
    services.act_payment(user, pay.pk, "submit", str(uuid.uuid4()))
    return pay


def parallel(*ops):
    barrier = Barrier(len(ops))

    def run(op):
        close_old_connections()
        try:
            barrier.wait(timeout=10)
            op()
            return "ok"
        except Conflict as exc:
            return exc.code
        finally:
            close_old_connections()

    with ThreadPoolExecutor(max_workers=len(ops)) as executor:
        return list(executor.map(run, ops))


def test_t01_transfer_and_t14_reconcile(data):
    p = pending(data)
    services.act_payment(data["owner"], p.pk, "approve", "approve")
    data["source"].refresh_from_db()
    data["destination"].refresh_from_db()
    assert data["source"].cached_balance == Decimal("80")
    assert data["destination"].cached_balance == Decimal("120")
    assert p.journaltransaction.entries.count() == 2
    assert services.reconcile() == []


def test_t02_duplicate_approve(data):
    p = pending(data)
    result = parallel(
        lambda: services.act_payment(data["owner"], p.pk, "approve", "a"),
        lambda: services.act_payment(data["owner"], p.pk, "approve", "a"),
    )
    assert result == ["ok", "ok"]
    assert JournalTransaction.objects.filter(payment=p).count() == 1
    assert LedgerEntry.objects.filter(journal__payment=p, side="DEBIT").count() == 1
    assert services.reconcile() == []


def test_t03_concurrent_overspend(data):
    p1, p2 = pending(data, amount="80"), pending(data, amount="80")
    # A second owner-role company cannot share the same source; two writers create
    # payments, while approvals are serialized by owner and account locks.
    result = parallel(
        lambda: services.act_payment(data["owner"], p1.pk, "approve", "a"),
        lambda: services.act_payment(data["owner"], p2.pk, "approve", "b"),
    )
    assert sorted(result) == ["insufficient_funds", "ok"]
    data["source"].refresh_from_db()
    assert data["source"].cached_balance == Decimal("20")
    assert Payment.objects.filter(status="EXECUTED").count() == 1
    assert services.reconcile() == []


def test_t04_failure_rolls_back(data):
    p = pending(data)

    def fail(journal, source, destination, amount):
        LedgerEntry.objects.create(journal=journal, account=source, side="DEBIT", amount=amount)
        raise RuntimeError("injected_failure")

    with patch("banking.services.write_entries", fail), pytest.raises(RuntimeError):
        services.act_payment(data["owner"], p.pk, "approve", "fail")
    p.refresh_from_db()
    assert p.status == "PENDING_APPROVAL"
    assert not JournalTransaction.objects.filter(payment=p).exists()
    assert services.reconcile() == []
    services.act_payment(data["owner"], p.pk, "approve", "fail")
    assert services.reconcile() == []


def test_t05_idempotency_conflict(data):
    body = {
        "source": data["source"].pk,
        "destination": data["destination"].pk,
        "amount": Decimal("10"),
        "purpose": "Services",
    }
    first = services.create_payment(data["owner"], data["company"].pk, body, "same")
    assert services.create_payment(data["owner"], data["company"].pk, body, "same") == first
    with pytest.raises(Conflict) as err:
        services.create_payment(data["owner"], data["company"].pk, {**body, "amount": Decimal("11")}, "same")
    assert err.value.code == "idempotency_conflict"
    assert Payment.objects.count() == 1


def test_t08_legal_approval_vs_cancel(data):
    p = pending(data, author=data["accountant"])
    result = parallel(
        lambda: services.act_payment(data["owner"], p.pk, "approve", "a"),
        lambda: services.act_payment(data["accountant"], p.pk, "cancel", "c"),
    )
    assert sorted(result) == ["invalid_state", "ok"]
    p.refresh_from_db()
    assert JournalTransaction.objects.filter(payment=p).count() == int(p.status == "EXECUTED")
    assert services.reconcile() == []


def test_t09_opposite_transfers(data):
    p1, p2 = pending(data, amount="25"), pending(data, amount="40", reverse=True)
    result = parallel(
        lambda: services.act_payment(data["owner"], p1.pk, "approve", "a"),
        lambda: services.act_payment(data["other"], p2.pk, "approve", "b"),
    )
    assert result == ["ok", "ok"]
    data["source"].refresh_from_db()
    assert data["source"].cached_balance == Decimal("115")
    assert services.reconcile() == []


def test_t12_database_rejects_imbalanced_journal(data):
    with pytest.raises(IntegrityError), transaction.atomic():
        journal = JournalTransaction.objects.create(kind="FUNDING", funding_key="bad")
        LedgerEntry.objects.create(journal=journal, account=data["source"], side="CREDIT", amount=1)
    assert not JournalTransaction.objects.filter(funding_key="bad").exists()


def test_database_rejects_balance_edit_and_history_change(data):
    with pytest.raises(IntegrityError), transaction.atomic():
        Account.objects.filter(pk=data["source"].pk).update(cached_balance=1000)
    with pytest.raises(IntegrityError), transaction.atomic():
        LedgerEntry.objects.all().update(amount=1)
    with pytest.raises(IntegrityError), transaction.atomic():
        AuditEvent.objects.all().delete()
    assert services.reconcile() == []


def test_database_rejects_append_to_committed_journal(data):
    journal = JournalTransaction.objects.first()
    with pytest.raises(IntegrityError), transaction.atomic():
        LedgerEntry.objects.create(journal=journal, account=data["source"], side="CREDIT", amount=1)


def test_database_rejects_fake_execution(data):
    p = pending(data)
    with pytest.raises(IntegrityError), transaction.atomic():
        Payment.objects.filter(pk=p.pk).update(status="EXECUTED")


def test_new_key_cannot_execute_twice(data):
    p = pending(data)
    a, _ = services.act_payment(data["owner"], p.pk, "approve", "one")
    b, _ = services.act_payment(data["owner"], p.pk, "approve", "two")
    assert a == b
    with pytest.raises(IntegrityError), transaction.atomic():
        Payment.objects.filter(pk=p.pk).update(amount=1)


def test_insufficient_funds_retains_pending(data):
    p = pending(data, amount="101")
    with pytest.raises(Conflict):
        services.act_payment(data["owner"], p.pk, "approve", "one")
    p.refresh_from_db()
    assert p.status == "PENDING_APPROVAL"
    assert not JournalTransaction.objects.filter(payment=p).exists()
