import os
from decimal import Decimal
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from banking.models import Account, Company, Membership
from banking.services import create_company, create_account, fund_demo


class Command(BaseCommand):
    help = "Create fictional companies, users and idempotent demo funding. Requires DEMO_PASSWORD."

    @transaction.atomic
    def handle(self, *args, **options):
        password = os.getenv("DEMO_PASSWORD")
        if not password:
            raise CommandError("Set DEMO_PASSWORD (minimum 8 characters)")
        validate_password(password)
        User = get_user_model()
        users = {}
        for name in ["owner", "accountant", "viewer", "partner"]:
            user, created = User.objects.get_or_create(
                email=f"{name}@demo.example", defaults={"first_name": name}
            )
            if created:
                user.set_password(password)
                user.save()
            users[name] = user
        company = Company.objects.filter(owner=users["owner"], name="ИП Куат Демо").first()
        if not company:
            company = create_company(users["owner"], "ИП Куат Демо")
        for name, role in [("accountant", "ACCOUNTANT"), ("viewer", "VIEWER")]:
            Membership.objects.get_or_create(company=company, user=users[name], defaults={"role": role})
        partner = Company.objects.filter(owner=users["partner"], name="ТОО Вектор Демо").first()
        if not partner:
            partner = create_company(users["partner"], "ТОО Вектор Демо")
        for comp, user, number in [
            (company, users["owner"], "DEMO-KUAT-001"),
            (partner, users["partner"], "DEMO-VECTOR-001"),
        ]:
            account = Account.objects.filter(number=number).first()
            if not account:
                account = create_account(user, comp.pk, "Основной счёт")
                account.number = number
                account.save(update_fields=["number"])
            fund_demo(account.pk, Decimal("1000000.00"), f"initial:{number}", user)
        self.stdout.write(
            self.style.SUCCESS(
                "Demo ready. owner/accountant/viewer/partner@demo.example; existing passwords unchanged."
            )
        )
