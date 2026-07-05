import logging

import structlog


class HealthAccessLogFilter(logging.Filter):
    """Hide Docker healthcheck noise from uvicorn access logs."""

    _QUIET_MARKERS = (
        '"GET /healthz ',
        '"GET /health ',
        '"GET /api/v1/health ',
    )

    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()
        return not any(marker in message for marker in self._QUIET_MARKERS)


def _attach_health_access_filter() -> None:
    filt = HealthAccessLogFilter()
    access_logger = logging.getLogger("uvicorn.access")
    if not any(isinstance(item, HealthAccessLogFilter) for item in access_logger.filters):
        access_logger.addFilter(filt)
    for handler in access_logger.handlers:
        if not any(isinstance(item, HealthAccessLogFilter) for item in handler.filters):
            handler.addFilter(filt)


def configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s:     %(name)s | %(message)s",
        force=True,
    )
    _attach_health_access_filter()
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.add_log_level,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )