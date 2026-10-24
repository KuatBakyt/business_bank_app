from django.core.management.base import BaseCommand, CommandError
from banking.services import reconcile


class Command(BaseCommand):
    help = "Read-only reconciliation of journal and cached account balances."

    def handle(self, *args, **options):
        errors = reconcile()
        if errors:
            raise CommandError("\n".join(errors))
        self.stdout.write(self.style.SUCCESS("OK: balanced ledger, matching caches, no negative balances"))
