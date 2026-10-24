import pytest
from django.contrib.auth import get_user_model
from django.core.cache import cache
from rest_framework.test import APIClient
from banking import services
from banking.models import Membership, Payment

pytestmark = pytest.mark.django_db(transaction=True)


def test_t06_foreign_company_and_account(data):
    client = data["client"]
    for url in [
        f"/api/v1/companies/{data['partner'].pk}/accounts/",
        f"/api/v1/accounts/{data['destination'].pk}/transactions/",
    ]:
        assert client.get(url).status_code == 404
    url = f"/api/v1/companies/{data['partner'].pk}/payments/"
    assert (
        client.post(
            url,
            {
                "source": str(data["destination"].pk),
                "destination": str(data["source"].pk),
                "amount": "1.00",
                "purpose": "test",
            },
            format="json",
            HTTP_IDEMPOTENCY_KEY="x",
        ).status_code
        == 404
    )


def create_api_payment(data):
    client = data["client"]
    url = f"/api/v1/companies/{data['company'].pk}/payments/"
    body = {
        "source": str(data["source"].pk),
        "destination": str(data["destination"].pk),
        "amount": "10.00",
        "purpose": "Services",
    }
    response = client.post(url, body, format="json", HTTP_IDEMPOTENCY_KEY="create")
    assert response.status_code == 201, response.data
    return response.data["id"]


def test_t07_accountant_cannot_approve(data):
    pid = create_api_payment(data)
    assert (
        data["client"]
        .post(f"/api/v1/payments/{pid}/submit/", {}, format="json", HTTP_IDEMPOTENCY_KEY="submit")
        .status_code
        == 200
    )
    data["client"].force_authenticate(data["accountant"])
    assert (
        data["client"]
        .post(f"/api/v1/payments/{pid}/approve/", {}, format="json", HTTP_IDEMPOTENCY_KEY="approve")
        .status_code
        == 403
    )
    assert Payment.objects.get(pk=pid).status == "PENDING_APPROVAL"


def test_t13_membership_revoked_with_live_jwt(data):
    client = APIClient()
    response = client.post(
        "/api/v1/auth/login/",
        {"email": data["accountant"].email, "password": "Demo-password-827!"},
        format="json",
    )
    client.credentials(HTTP_AUTHORIZATION="Bearer " + response.data["access"])
    url = f"/api/v1/companies/{data['company'].pk}/accounts/"
    assert client.get(url).status_code == 200
    member = Membership.objects.get(company=data["company"], user=data["accountant"])
    services.change_member(data["owner"], data["company"].pk, member.pk, {"is_active": False})
    assert client.get(url).status_code == 404


def test_jwt_refresh_rotation_and_logout(data):
    client = APIClient()
    login = client.post(
        "/api/v1/auth/login/",
        {"email": data["owner"].email.upper(), "password": "Demo-password-827!"},
        format="json",
    )
    assert login.status_code == 200
    old = login.data["refresh"]
    new = client.post("/api/v1/auth/refresh/", {"refresh": old}, format="json")
    assert new.status_code == 200
    assert client.post("/api/v1/auth/refresh/", {"refresh": old}, format="json").status_code == 401
    client.credentials(HTTP_AUTHORIZATION="Bearer " + new.data["access"])
    assert (
        client.post("/api/v1/auth/logout/", {"refresh": new.data["refresh"]}, format="json").status_code
        == 204
    )
    assert (
        client.post("/api/v1/auth/refresh/", {"refresh": new.data["refresh"]}, format="json").status_code
        == 401
    )


def test_validation_and_required_idempotency(data):
    client = data["client"]
    url = f"/api/v1/companies/{data['company'].pk}/payments/"
    body = {
        "source": str(data["source"].pk),
        "destination": str(data["destination"].pk),
        "amount": "1.001",
        "purpose": "test",
    }
    assert client.post(url, body, format="json", HTTP_IDEMPOTENCY_KEY="x").status_code == 400
    body["amount"] = "1.00"
    assert client.post(url, body, format="json").status_code == 400
    body["status"] = "EXECUTED"
    assert client.post(url, body, format="json", HTTP_IDEMPOTENCY_KEY="x").status_code == 400
    assert Payment.objects.count() == 0


def test_viewer_cannot_write(data):
    data["client"].force_authenticate(data["viewer"])
    response = data["client"].post(
        f"/api/v1/companies/{data['company'].pk}/accounts/", {"name": "No"}, format="json"
    )
    assert response.status_code == 403


def test_owner_role_protected(data):
    member = Membership.objects.get(user=data["owner"], company=data["company"])
    response = data["client"].patch(
        f"/api/v1/companies/{data['company'].pk}/members/{member.pk}/", {"role": "VIEWER"}, format="json"
    )
    assert response.status_code == 403


def test_recipient_minimal_fields_and_throttle(data):
    client = data["client"]
    body = {"number": data["destination"].number}
    response = client.post("/api/v1/recipients/resolve/", body, format="json")
    assert response.status_code == 200
    assert set(response.data) == {"id", "number", "company_name"}
    for _ in range(4):
        assert client.post("/api/v1/recipients/resolve/", body, format="json").status_code == 200
    assert client.post("/api/v1/recipients/resolve/", body, format="json").status_code == 429


def test_login_limit_and_registration():
    client = APIClient()
    response = client.post(
        "/api/v1/auth/register/",
        {"email": "NEW@example.test", "password": "Good-password-827!"},
        format="json",
    )
    assert response.status_code == 201, response.data
    assert get_user_model().objects.filter(email="new@example.test").exists()
    cache.clear()
    for _ in range(5):
        assert (
            client.post(
                "/api/v1/auth/login/", {"email": "no@example.test", "password": "bad"}, format="json"
            ).status_code
            == 401
        )
    assert (
        client.post(
            "/api/v1/auth/login/", {"email": "no@example.test", "password": "bad"}, format="json"
        ).status_code
        == 429
    )


def test_health_and_error_envelope(data):
    assert data["client"].get("/health/live/").status_code == 200
    assert data["client"].get("/health/ready/").status_code == 200
    response = data["client"].post("/api/v1/companies/", {}, format="json")
    assert response.status_code == 400
    assert set(response.data) == {"code", "message", "fields", "request_id"}
    assert response.data["request_id"]
