from django.contrib import admin
from .models import (
    Account,
    AuditEvent,
    Company,
    JournalTransaction,
    LedgerEntry,
    Membership,
    Payment,
    StatementExport,
)


class ReadOnlyAdmin(admin.ModelAdmin):
    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


for model in [
    Account,
    AuditEvent,
    Company,
    JournalTransaction,
    LedgerEntry,
    Membership,
    Payment,
    StatementExport,
]:
    admin.site.register(model, ReadOnlyAdmin)
