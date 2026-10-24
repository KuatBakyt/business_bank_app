import pytest
from decimal import Decimal
from django.core.cache import cache
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient
from banking.models import Membership
from banking.services import create_company, create_account, fund_demo


@pytest.fixture(autouse=True)
def clear_cache():
    cache.clear()


@pytest.fixture
def data(transactional_db):
    User = get_user_model()
    owner = User.objects.create_user("owner@example.test", "Demo-password-827!")
    other = User.objects.create_user("other@example.test", "Demo-password-827!")
    accountant = User.objects.create_user("accountant@example.test", "Demo-password-827!")
    viewer = User.objects.create_user("viewer@example.test", "Demo-password-827!")
    company = create_company(owner, "Company A")
    partner = create_company(other, "Company B")
    Membership.objects.create(user=accountant, company=company, role="ACCOUNTANT")
    Membership.objects.create(user=viewer, company=company, role="VIEWER")
    source = create_account(owner, company.pk, "Main")
    destination = create_account(other, partner.pk, "Partner")
    fund_demo(source.pk, Decimal("100.00"), "fund-source", owner)
    fund_demo(destination.pk, Decimal("100.00"), "fund-destination", other)
    client = APIClient()
    client.force_authenticate(owner)
    return locals()
