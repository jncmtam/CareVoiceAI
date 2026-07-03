from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.exc import IntegrityError

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.errors import APIError
from app.core.logging import configure_logging
from app.db.init_db import create_tables, seed_demo_data
from app.db.session import AsyncSessionLocal
from app.middleware.rate_limit import RateLimitMiddleware
from app.middleware.request_context import RequestContextMiddleware
from app.schemas.common import APIErrorBody, APIErrorEnvelope, stringify_details
from app.utils.datetime import now_utc

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    configure_logging()
    settings.local_storage_dir.mkdir(parents=True, exist_ok=True)
    if settings.auto_create_tables:
        await create_tables()
    async with AsyncSessionLocal() as session:
        await seed_demo_data(session, settings)
    yield


def create_app() -> FastAPI:
    settings.local_storage_dir.mkdir(parents=True, exist_ok=True)
    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        openapi_url=f"{settings.api_v1_prefix}/openapi.json",
        docs_url=f"{settings.api_v1_prefix}/docs",
        redoc_url=f"{settings.api_v1_prefix}/redoc",
        lifespan=lifespan,
    )
    app.add_middleware(RequestContextMiddleware)
    app.add_middleware(RateLimitMiddleware, settings=settings)
    app.add_middleware(GZipMiddleware, minimum_size=1024)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("x-content-type-options", "nosniff")
        response.headers.setdefault("x-frame-options", "DENY")
        response.headers.setdefault("referrer-policy", "no-referrer")
        return response

    app.include_router(api_router, prefix=settings.api_v1_prefix)

    @app.get("/healthz")
    async def healthz() -> dict:
        return {"status": "ok", "checked_at": now_utc().isoformat()}

    app.mount("/media", StaticFiles(directory=settings.local_storage_dir), name="media")

    register_exception_handlers(app)
    return app


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(APIError)
    async def handle_api_error(request: Request, exc: APIError) -> JSONResponse:
        return _error_response(
            request=request,
            status_code=exc.status_code,
            code=exc.code,
            message=exc.message,
            details=stringify_details(exc.details),
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
        details = {
            ".".join(str(part) for part in error.get("loc", [])): error.get("msg", "")
            for error in exc.errors()
        }
        return _error_response(
            request=request,
            status_code=422,
            code="validation_error",
            message="Dữ liệu gửi lên không hợp lệ.",
            details=details,
        )

    @app.exception_handler(HTTPException)
    async def handle_http_error(request: Request, exc: HTTPException) -> JSONResponse:
        return _error_response(
            request=request,
            status_code=exc.status_code,
            code="invalid_request" if exc.status_code < 500 else "internal_error",
            message=str(exc.detail),
        )

    @app.exception_handler(IntegrityError)
    async def handle_integrity_error(request: Request, exc: IntegrityError) -> JSONResponse:
        _ = exc
        return _error_response(
            request=request,
            status_code=409,
            code="conflict",
            message="Dữ liệu đã tồn tại hoặc vi phạm ràng buộc.",
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
        _ = exc
        return _error_response(
            request=request,
            status_code=500,
            code="internal_error",
            message="Hệ thống đang bận. Vui lòng thử lại sau.",
        )


def _error_response(
    *,
    request: Request,
    status_code: int,
    code: str,
    message: str,
    details: dict[str, str] | None = None,
) -> JSONResponse:
    trace_id = getattr(request.state, "trace_id", None)
    envelope = APIErrorEnvelope(
        error=APIErrorBody(
            code=code,
            message=message,
            details=details or {},
            trace_id=trace_id,
        )
    )
    return JSONResponse(status_code=status_code, content=envelope.model_dump(mode="json"))


app = create_app()
