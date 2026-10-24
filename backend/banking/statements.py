import csv
import io
from datetime import datetime, time, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from zoneinfo import ZoneInfo
from django.db import transaction
from django.core.files.base import ContentFile
from django.utils import timezone as dj_timezone
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Table, TableStyle
from xml.sax.saxutils import escape
from .models import Account, LedgerEntry, StatementExport


def boundaries(start, end):
    zone = ZoneInfo("Asia/Almaty")
    return (
        datetime.combine(start, time.min, zone).astimezone(timezone.utc),
        datetime.combine(end + timedelta(days=1), time.min, zone).astimezone(timezone.utc),
    )


def safe_csv(value):
    value = str(value)
    return "'" + value if value.lstrip().startswith(("=", "+", "-", "@", "\t", "\r", "\n")) else value


@transaction.atomic
def snapshot(export):
    account = (
        Account.objects.select_for_update(of=("self",)).select_related("company").get(pk=export.account_id)
    )
    lo, hi = boundaries(export.date_from, export.date_to)
    entries = (
        LedgerEntry.objects.filter(account=account)
        .select_related("journal__payment")
        .order_by("journal__posted_at", "id")
    )
    opening = Decimal(0)
    incoming = Decimal(0)
    outgoing = Decimal(0)
    rows = []
    for entry in entries.filter(journal__posted_at__lt=hi):
        signed = entry.amount if entry.side == "CREDIT" else -entry.amount
        if entry.journal.posted_at < lo:
            opening += signed
        else:
            if signed > 0:
                incoming += signed
            else:
                outgoing -= signed
            rows.append(
                [
                    str(entry.journal_id),
                    entry.journal.posted_at.isoformat(),
                    entry.journal.payment.purpose if entry.journal.payment_id else "Тестовое пополнение",
                    str(entry.amount) if signed > 0 else "",
                    str(entry.amount) if signed < 0 else "",
                ]
            )
    return {
        "account": account.number,
        "company": account.company.name,
        "currency": "KZT",
        "opening": str(opening),
        "incoming": str(incoming),
        "outgoing": str(outgoing),
        "closing": str(opening + incoming - outgoing),
        "rows": rows,
    }


def render_csv(data):
    buf = io.StringIO(newline="")
    writer = csv.writer(buf)
    for key in ("company", "account", "currency", "opening", "incoming", "outgoing", "closing"):
        writer.writerow([key, safe_csv(data[key])])
    writer.writerow(["Учебная выписка"])
    writer.writerow(["ID операции", "Время UTC", "Назначение", "Приход", "Расход"])
    for row in data["rows"]:
        writer.writerow([safe_csv(cell) for cell in row])
    return buf.getvalue().encode("utf-8-sig")


def render_pdf(data):
    font = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    if not font.exists():
        raise RuntimeError("pdf_font_missing")
    pdfmetrics.registerFont(TTFont("DejaVu", str(font)))
    styles = getSampleStyleSheet()
    for style in styles.byName.values():
        style.fontName = "DejaVu"
    styles["Normal"].fontSize = 8
    styles["Normal"].leading = 11
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, rightMargin=32, leftMargin=32)
    story = [Paragraph("Учебная выписка Business Bank", styles["Title"])]
    for key in ("company", "account", "currency", "opening", "incoming", "outgoing", "closing"):
        story.append(Paragraph(f"{key}: {escape(str(data[key]))}", styles["Normal"]))
    rows = [["Операция и дата", "Назначение", "Приход", "Расход"]]
    for row in data["rows"]:
        rows.append([row[0] + "\n" + row[1], row[2], row[3], row[4]])
    rendered = [
        [Paragraph(escape(str(cell)).replace("\n", "<br/>"), styles["Normal"]) for cell in row]
        for row in rows
    ]
    table = Table(rendered, colWidths=[190, 200, 67, 67], repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#DBE5F1")),
                ("GRID", (0, 0), (-1, -1), 0.3, colors.lightgrey),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
            ]
        )
    )
    story.append(table)
    doc.build(story)
    return buf.getvalue()


@transaction.atomic
def generate(export_id):
    export = StatementExport.objects.select_for_update().get(pk=export_id)
    if export.status != "QUEUED":
        return
    export.status = "PROCESSING"
    export.save(update_fields=["status"])
    data = snapshot(export)
    data["period"] = f"{export.date_from} — {export.date_to} (Asia/Almaty)"
    data["rows"].insert(0, ["Период", data["period"], "", "", ""])
    content = render_csv(data) if export.format == "csv" else render_pdf(data)
    # Deterministic path: a crash before DB commit can leave an orphan, never a public file.
    from django.core.files.storage import default_storage

    name = f"statements/{export.pk}.{export.format}"
    if default_storage.exists(name):
        default_storage.delete(name)
    export.private_file.name = default_storage.save(name, ContentFile(content))
    export.status = "READY"
    export.expires_at = dj_timezone.now() + timedelta(hours=24)
    export.save(update_fields=["private_file", "status", "expires_at"])
