import json
import logging
import time
import uuid


class JsonFormatter(logging.Formatter):
    def format(self, record):
        return json.dumps(
            {
                "event": record.getMessage(),
                "level": record.levelname,
                "request_id": getattr(record, "request_id", None),
                "duration_ms": getattr(record, "duration_ms", None),
            },
            ensure_ascii=False,
        )


class RequestMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request.request_id = str(uuid.uuid4())
        start = time.monotonic()
        response = self.get_response(request)
        response["X-Request-ID"] = request.request_id
        logging.getLogger("requests").info(
            "http_response",
            extra={
                "request_id": request.request_id,
                "duration_ms": round((time.monotonic() - start) * 1000, 2),
            },
        )
        return response
