import uuid
from django.conf import settings
from django.db import models
from django.db.models import Q, F


class Base(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        abstract = True
        ordering = ["created_at", "id"]


class Company(Base):
    name = models.CharField(max_length=200)
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)


class Membership(Base):
    class Role(models.TextChoices):
        OWNER = "OWNER"
        ACCOUNTANT = "ACCOUNTANT"
        VIEWER = "VIEWER"

    company = models.ForeignKey(Company, on_delete=models.PROTECT)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    role = models.CharField(max_length=16, choices=Role.choices)
    is_active = models.BooleanField(default=True)

    class Meta(Base.Meta):
        constraints = [
            models.UniqueConstraint(fields=["company", "user"], name="membership_unique"),
            models.UniqueConstraint(fields=["company"], condition=Q(role="OWNER"), name="one_owner"),
        ]


class Account(Base):
    company = models.ForeignKey(Company, null=True, blank=True, on_delete=models.PROTECT)
    number = models.CharField(max_length=45, unique=True)
    name = models.CharField(max_length=100)
    currency = models.CharField(max_length=3, default="KZT", editable=False)
    status = models.CharField(
        max_length=8, choices=[("ACTIVE", "ACTIVE"), ("CLOSED", "CLOSED")], default="ACTIVE"
    )
    cached_balance = models.DecimalField(max_digits=20, decimal_places=2, default=0)
    closed_at = models.DateTimeField(null=True, blank=True)
    is_system = models.BooleanField(default=False)

    class Meta(Base.Meta):
        constraints = [
            models.CheckConstraint(condition=Q(cached_balance__gte=0), name="nonnegative_balance"),
            models.CheckConstraint(condition=Q(currency="KZT"), name="kzt_only"),
            models.CheckConstraint(
                condition=Q(is_system=True, company__isnull=True) | Q(is_system=False, company__isnull=False),
                name="system_or_company",
            ),
        ]


class Payment(Base):
    class Status(models.TextChoices):
        DRAFT = "DRAFT"
        PENDING = "PENDING_APPROVAL"
        EXECUTED = "EXECUTED"
        REJECTED = "REJECTED"
        CANCELLED = "CANCELLED"

    source = models.ForeignKey(Account, related_name="outgoing", on_delete=models.PROTECT)
    destination = models.ForeignKey(Account, related_name="incoming", on_delete=models.PROTECT)
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    purpose = models.CharField(max_length=500)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.DRAFT, db_index=True)
    author = models.ForeignKey(settings.AUTH_USER_MODEL, related_name="authored", on_delete=models.PROTECT)
    approver = models.ForeignKey(
        settings.AUTH_USER_MODEL, related_name="approved", null=True, blank=True, on_delete=models.PROTECT
    )
    reason = models.CharField(max_length=500, blank=True)
    executed_at = models.DateTimeField(null=True, blank=True, db_index=True)

    class Meta(Base.Meta):
        constraints = [
            models.CheckConstraint(
                condition=Q(amount__gt=0, amount__lte=100000000), name="payment_amount_range"
            ),
            models.CheckConstraint(condition=~Q(source=F("destination")), name="different_accounts"),
        ]


class JournalTransaction(Base):
    payment = models.OneToOneField(Payment, null=True, blank=True, on_delete=models.PROTECT)
    funding_key = models.CharField(max_length=100, unique=True, null=True, blank=True)
    kind = models.CharField(max_length=10, choices=[("TRANSFER", "TRANSFER"), ("FUNDING", "FUNDING")])
    posted_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta(Base.Meta):
        constraints = [
            models.CheckConstraint(
                condition=Q(kind="TRANSFER", payment__isnull=False, funding_key__isnull=True)
                | Q(kind="FUNDING", payment__isnull=True, funding_key__isnull=False),
                name="journal_reference",
            )
        ]


class LedgerEntry(Base):
    journal = models.ForeignKey(JournalTransaction, on_delete=models.PROTECT, related_name="entries")
    account = models.ForeignKey(Account, on_delete=models.PROTECT, related_name="entries")
    side = models.CharField(max_length=6, choices=[("DEBIT", "DEBIT"), ("CREDIT", "CREDIT")])
    amount = models.DecimalField(max_digits=20, decimal_places=2)

    class Meta(Base.Meta):
        constraints = [
            models.CheckConstraint(condition=Q(amount__gt=0), name="positive_entry"),
            models.CheckConstraint(condition=Q(side__in=["DEBIT", "CREDIT"]), name="valid_side"),
        ]


class IdempotencyRecord(Base):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    action = models.CharField(max_length=150)
    key = models.CharField(max_length=128)
    request_hash = models.CharField(max_length=64)
    status_code = models.PositiveSmallIntegerField(default=200)
    response = models.JSONField(null=True)

    class Meta(Base.Meta):
        constraints = [models.UniqueConstraint(fields=["user", "action", "key"], name="idempotency_unique")]


class AuditEvent(Base):
    actor = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.PROTECT)
    company = models.ForeignKey(Company, on_delete=models.PROTECT)
    action = models.CharField(max_length=80)
    entity_id = models.UUIDField()
    request_id = models.CharField(max_length=36, blank=True)
    changes = models.JSONField(default=dict)


class StatementExport(Base):
    account = models.ForeignKey(Account, on_delete=models.PROTECT)
    requested_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT)
    date_from = models.DateField()
    date_to = models.DateField()
    format = models.CharField(max_length=3, choices=[("csv", "csv"), ("pdf", "pdf")])
    status = models.CharField(max_length=12, default="QUEUED")
    private_file = models.FileField(upload_to="statements/", blank=True)
    error_code = models.CharField(max_length=50, blank=True)
    expires_at = models.DateTimeField(null=True, blank=True)
