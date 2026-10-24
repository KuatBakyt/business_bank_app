import logging
from rest_framework.exceptions import APIException
from rest_framework.views import exception_handler


class Conflict(APIException):
    status_code = 409
    default_code = "conflict"

    def __init__(self, code, message):
        self.code = code
        super().__init__(message, code)


def handler(exc, context):
    response = exception_handler(exc, context)
    request = context.get("request")
    request_id = getattr(request, "request_id", "")
    if response is None:
        logging.getLogger(__name__).error("unhandled_error", extra={"request_id": request_id})
        from rest_framework.response import Response

        return Response(
            {
                "code": "internal_error",
                "message": "Внутренняя ошибка",
                "fields": {},
                "request_id": request_id,
            },
            status=500,
        )
    codes = {
        400: "validation_error",
        401: "unauthenticated",
        403: "forbidden",
        404: "not_found",
        405: "method_not_allowed",
        429: "rate_limited",
    }
    detail = response.data
    response.data = {
        "code": getattr(exc, "code", codes.get(response.status_code, "error")),
        "message": str(detail.get("detail", "Проверьте данные"))
        if isinstance(detail, dict)
        else "Проверьте данные",
        "fields": detail if isinstance(detail, dict) and "detail" not in detail else {},
        "request_id": request_id,
    }
    return response
