from celery import shared_task
from django.db import transaction
from django.utils import timezone
from .models import StatementExport
from .statements import generate


@shared_task(bind=True, max_retries=3)
def generate_statement(self, export_id):
    try:
        generate(export_id)
    except Exception as exc:
        if self.request.retries >= self.max_retries:
            StatementExport.objects.filter(pk=export_id, status="QUEUED").update(
                status="FAILED", error_code="generation_failed"
            )
            return
        raise self.retry(exc=RuntimeError("statement_retry"), countdown=10) from exc


@shared_task
def maintain_exports():
    for export_id in StatementExport.objects.filter(status="QUEUED").values_list("id", flat=True)[:100]:
        generate_statement.delay(str(export_id))
    for export_id in StatementExport.objects.filter(
        status="READY", expires_at__lte=timezone.now()
    ).values_list("id", flat=True)[:100]:
        with transaction.atomic():
            export = StatementExport.objects.select_for_update().get(pk=export_id)
            if export.status == "READY" and export.expires_at <= timezone.now():
                export.private_file.delete(save=False)
                export.status = "EXPIRED"
                export.save(update_fields=["private_file", "status"])
