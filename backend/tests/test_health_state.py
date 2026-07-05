import logging

from app.core.config import Settings
from app.core.logging import HealthAccessLogFilter
from app.services import health_state


def test_health_access_log_filter_hides_only_health_requests() -> None:
    filt = HealthAccessLogFilter()
    health = logging.LogRecord(
        name="uvicorn.access",
        level=logging.INFO,
        pathname="",
        lineno=0,
        msg='%s - "%s" %s',
        args=("127.0.0.1:1234", "GET /healthz HTTP/1.1", "200"),
        exc_info=None,
    )
    api = logging.LogRecord(
        name="uvicorn.access",
        level=logging.INFO,
        pathname="",
        lineno=0,
        msg='%s - "%s" %s',
        args=("127.0.0.1:1234", "GET /api/v1/me HTTP/1.1", "200"),
        exc_info=None,
    )
    assert filt.filter(health) is False
    assert filt.filter(api) is True


def test_health_snapshot_only_updates_on_state_change() -> None:
    health_state._snapshot = None
    settings = Settings(app_name="CareVoice Test", app_env="test")

    first = health_state.get_health_snapshot(settings)
    second = health_state.get_health_snapshot(settings)

    assert first.status == "ok"
    assert second.checked_at == first.checked_at
    assert second.app == first.app
    assert second.environment == first.environment