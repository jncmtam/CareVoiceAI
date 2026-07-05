import time
from uuid import uuid4

import structlog
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import Response

logger = structlog.get_logger("carevoice.http")


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        trace_id = request.headers.get("x-request-id") or f"req_{uuid4().hex[:20]}"
        request.state.trace_id = trace_id
        structlog.contextvars.bind_contextvars(trace_id=trace_id)
        started = time.perf_counter()
        path = request.url.path
        method = request.method
        try:
            response = await call_next(request)
            response.headers["x-request-id"] = trace_id
            duration_ms = round((time.perf_counter() - started) * 1000, 1)
            if response.status_code >= 500:
                logger.error(
                    "request_failed",
                    method=method,
                    path=path,
                    status=response.status_code,
                    duration_ms=duration_ms,
                )
            elif response.status_code >= 400:
                logger.warning(
                    "request_client_error",
                    method=method,
                    path=path,
                    status=response.status_code,
                    duration_ms=duration_ms,
                )
            else:
                logger.info(
                    "request_completed",
                    method=method,
                    path=path,
                    status=response.status_code,
                    duration_ms=duration_ms,
                )
            return response
        except Exception:
            duration_ms = round((time.perf_counter() - started) * 1000, 1)
            logger.exception(
                "request_failed",
                method=method,
                path=path,
                status=500,
                duration_ms=duration_ms,
            )
            raise
        finally:
            structlog.contextvars.clear_contextvars()

