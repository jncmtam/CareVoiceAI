from uuid import uuid4

import structlog
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import Response


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        trace_id = request.headers.get("x-request-id") or f"req_{uuid4().hex[:20]}"
        request.state.trace_id = trace_id
        structlog.contextvars.bind_contextvars(trace_id=trace_id)
        try:
            response = await call_next(request)
            response.headers["x-request-id"] = trace_id
            return response
        finally:
            structlog.contextvars.clear_contextvars()

