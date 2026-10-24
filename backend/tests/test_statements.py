import csv
import io
from datetime import date, datetime, timezone
from decimal import Decimal
from unittest.mock import patch
import pytest
from django.core.management import call_command
from django.utils import timezone as dj_timezone
from banking.models import StatementExport
from banking.services import fund_demo, reconcile
from banking.statements import boundaries, generate, render_csv, render_pdf, snapshot
from banking.tasks import maintain_exports

pytestmark = pytest.mark.django_db(transaction=True)


@pytest.fixture(autouse=True)
def private_storage(settings, tmp_path):
    settings.MEDIA_ROOT = tmp_path


def test_t10_demo_funding_idempotent(data):
    data["source"].refresh_from_db()
    before = data["source"].cached_balance
    fund_demo(data["source"].pk, Decimal("100"), "fund-source", data["owner"])
    data["source"].refresh_from_db()
    assert data["source"].cached_balance == before
    assert reconcile() == []


def test_t10_seed_command_idempotent(data, monkeypatch):
    monkeypatch.setenv("DEMO_PASSWORD", "Seed-only-safe-827!")
    call_command("seed_demo")
    from banking.models import Account

    a = Account.objects.get(number="DEMO-KUAT-001")
    assert a.cached_balance == Decimal("1000000")
    call_command("seed_demo")
    a.refresh_from_db()
    assert a.cached_balance == Decimal("1000000")
    assert reconcile() == []


def test_t11_boundaries_and_snapshot(data):
    lo, hi = boundaries(date(2026, 10, 24), date(2026, 10, 24))
    assert lo == datetime(2026, 10, 23, 19, tzinfo=timezone.utc)
    assert hi == datetime(2026, 10, 24, 19, tzinfo=timezone.utc)
    # Funding at the exact lower boundary is included; at the upper boundary excluded.
    with patch("django.utils.timezone.now", return_value=lo):
        fund_demo(data["source"].pk, Decimal("7"), "at-lower")
    with patch("django.utils.timezone.now", return_value=hi):
        fund_demo(data["source"].pk, Decimal("9"), "at-upper")
    export = StatementExport.objects.create(
        account=data["source"],
        requested_by=data["owner"],
        date_from=date(2026, 10, 24),
        date_to=date(2026, 10, 24),
        format="csv",
    )
    data_set = snapshot(export)
    assert any(row[3] == "7.00" for row in data_set["rows"])
    assert not any(row[3] == "9.00" for row in data_set["rows"])
    assert Decimal(data_set["opening"]) + Decimal(data_set["incoming"]) - Decimal(
        data_set["outgoing"]
    ) == Decimal(data_set["closing"])


def test_export_duplicate_task_and_private_download(data):
    today = dj_timezone.now().date()
    export = StatementExport.objects.create(
        account=data["source"], requested_by=data["owner"], date_from=today, date_to=today, format="csv"
    )
    generate(export.pk)
    export.refresh_from_db()
    name = export.private_file.name
    generate(export.pk)
    export.refresh_from_db()
    assert export.private_file.name == name
    response = data["client"].get(f"/api/v1/statement-exports/{export.pk}/download/")
    assert response.status_code == 200
    assert b"opening" in b"".join(response.streaming_content)
    data["client"].force_authenticate(data["other"])
    assert data["client"].get(f"/api/v1/statement-exports/{export.pk}/download/").status_code == 404
    export.expires_at = dj_timezone.now()
    export.save(update_fields=["expires_at"])
    maintain_exports()
    export.refresh_from_db()
    assert export.status == "EXPIRED"
    assert not export.private_file


def test_csv_formula_and_pdf(data):
    content = {
        "company": "=cmd()",
        "account": data["source"].number,
        "currency": "KZT",
        "opening": "0",
        "incoming": "1",
        "outgoing": "0",
        "closing": "1",
        "rows": [["id", "2026-01-01", "@bad", "1", ""]],
    }
    rows = list(csv.reader(io.StringIO(render_csv(content).decode("utf-8-sig"))))
    assert rows[0][1].startswith("'=")
    assert rows[-1][2].startswith("'@")
    assert render_pdf(content).startswith(b"%PDF-")


def test_statement_api_validates_period(data):
    client = data["client"]
    url = f"/api/v1/accounts/{data['source'].pk}/statement-exports/"
    assert (
        client.post(
            url, {"date_from": "2026-01-01", "date_to": "2027-01-02", "format": "csv"}, format="json"
        ).status_code
        == 400
    )
    assert (
        client.post(
            url, {"date_from": "2026-01-01", "date_to": "2026-01-31", "format": "csv"}, format="json"
        ).status_code
        == 202
    )


def test_statement_history_is_scoped_to_company(data):
    today = dj_timezone.now().date()
    export = StatementExport.objects.create(
        account=data["source"], requested_by=data["owner"], date_from=today, date_to=today, format="csv"
    )
    url = f"/api/v1/accounts/{data['source'].pk}/statement-exports/"
    response = data["client"].get(url)
    assert response.status_code == 200
    assert response.data["count"] == 1
    assert response.data["results"][0]["id"] == str(export.pk)
    data["client"].force_authenticate(data["other"])
    assert data["client"].get(url).status_code == 404
