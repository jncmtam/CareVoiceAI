from collections import defaultdict, deque
from time import monotonic

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import JSONResponse, Response

from app.core.config import Settings


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, settings: Settings) -> None:
        super().__init__(app)
        self.settings = settings
        self.requests: dict[str, deque[float]] = defaultdict(deque)

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        if not self.settings.rate_limit_enabled or request.url.path in {"/healthz", "/health"} or request.url.path.endswith("/health"):
            return await call_next(request)
        key = self._key(request)
        now = monotonic()
        window_start = now - self.settings.rate_limit_window_seconds
        bucket = self.requests[key]
        while bucket and bucket[0] < window_start:
            bucket.popleft()
        if len(bucket) >= self.settings.rate_limit_requests:
            trace_id = getattr(request.state, "trace_id", None)
            return JSONResponse(
                status_code=429,
                content={
                    "error": {
                        "code": "rate_limited",
                        "message": "Bạn thao tác quá nhanh. Vui lòng thử lại sau.",
                        "details": {},
                        "trace_id": trace_id,
                    }
                },
                headers={"retry-after": str(self.settings.rate_limit_window_seconds)},
            )
        bucket.append(now)
        return await call_next(request)

    def _key(self, request: Request) -> str:
        forwarded = request.headers.get("x-forwarded-for")
        ip = (forwarded.split(",")[0].strip() if forwarded else None) or (
            request.client.host if request.client else "unknown"
        )
        user_hint = request.headers.get("authorization", "")[-16:]
        return f"{ip}:{user_hint}:{request.url.path}"
