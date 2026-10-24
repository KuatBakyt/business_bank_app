from django.contrib import admin
from django.urls import path
from django.http import JsonResponse
from django.db import connection
from django.core.cache import cache
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView, SpectacularRedocView
from users.api import RegisterView, LoginView, RefreshView, LogoutView, MeView
from banking import api


def live(request):
    return JsonResponse({"status": "ok"})


def ready(request):
    try:
        with connection.cursor() as cur:
            cur.execute("SELECT 1")
        cache.set("health:ready", "ok", 5)
        if cache.get("health:ready") != "ok":
            raise RuntimeError("cache")
    except Exception:
        return JsonResponse({"status": "unavailable"}, status=503)
    return JsonResponse({"status": "ok"})


urlpatterns = [
    path("admin/", admin.site.urls),
    path("health/live/", live),
    path("health/ready/", ready),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema")),
    path("api/redoc/", SpectacularRedocView.as_view(url_name="schema")),
    path("api/v1/auth/register/", RegisterView.as_view()),
    path("api/v1/auth/login/", LoginView.as_view()),
    path("api/v1/auth/refresh/", RefreshView.as_view()),
    path("api/v1/auth/logout/", LogoutView.as_view()),
    path("api/v1/auth/me/", MeView.as_view()),
    path("api/v1/companies/", api.CompanyList.as_view()),
    path("api/v1/companies/<uuid:company_id>/members/", api.MemberList.as_view()),
    path("api/v1/companies/<uuid:company_id>/members/<uuid:member_id>/", api.MemberDetail.as_view()),
    path("api/v1/companies/<uuid:company_id>/accounts/", api.AccountList.as_view()),
    path("api/v1/accounts/<uuid:account_id>/close/", api.AccountClose.as_view()),
    path("api/v1/recipients/resolve/", api.RecipientResolve.as_view()),
    path("api/v1/companies/<uuid:company_id>/payments/", api.PaymentList.as_view()),
    path("api/v1/payments/<uuid:payment_id>/", api.PaymentDetail.as_view()),
    path("api/v1/payments/<uuid:payment_id>/submit/", api.Submit.as_view()),
    path("api/v1/payments/<uuid:payment_id>/approve/", api.Approve.as_view()),
    path("api/v1/payments/<uuid:payment_id>/reject/", api.Reject.as_view()),
    path("api/v1/payments/<uuid:payment_id>/cancel/", api.Cancel.as_view()),
    path("api/v1/accounts/<uuid:account_id>/transactions/", api.EntryList.as_view()),
    path("api/v1/accounts/<uuid:account_id>/statement-exports/", api.StatementCreate.as_view()),
    path("api/v1/statement-exports/<uuid:export_id>/", api.StatementDetail.as_view()),
    path("api/v1/statement-exports/<uuid:export_id>/download/", api.StatementDownload.as_view()),
    path("api/v1/companies/<uuid:company_id>/audit/", api.AuditList.as_view()),
]
