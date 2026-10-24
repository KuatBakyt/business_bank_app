from collections.abc import Mapping
import hashlib
from django.core.cache import cache
from rest_framework.throttling import BaseThrottle


class FixedWindow(BaseThrottle):
    limit = 5
    scope = "sensitive"

    def allow_request(self, request, view):
        keys = self.keys(request)
        counts = []
        for key in keys:
            key = hashlib.sha256(key.encode()).hexdigest()
            if cache.add(key, 1, timeout=60):
                counts.append(1)
            else:
                try:
                    counts.append(cache.incr(key))
                except ValueError:
                    counts.append(self.limit + 1)
        return all(count <= self.limit for count in counts)

    def keys(self, request):
        return [f"{self.scope}:ip:{self.get_ident(request)}"]

    def wait(self):
        return 60


class LoginThrottle(FixedWindow):
    scope = "login"

    def keys(self, request):
        return super().keys(request) + [
            f"{self.scope}:email:{str(request.data.get('email', '')).strip().lower()}"
        ]


class RecipientThrottle(FixedWindow):
    scope = "recipient"

    def keys(self, request):
        return super().keys(request) + [f"{self.scope}:user:{request.user.pk}"]


class WriteThrottle(FixedWindow):
    scope = "write"
    limit = 60

    def allow_request(self, request, view):
        if request.method in ("GET", "HEAD", "OPTIONS"):
            return True
        return super().allow_request(request, view)

    def keys(self, request):
        return (
            [f"{self.scope}:user:{request.user.pk}"]
            if request.user.is_authenticated
            else [f"{self.scope}:ip:{self.get_ident(request)}"]
        )
