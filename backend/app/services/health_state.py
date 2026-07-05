from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from app.core.config import Settings
from app.utils.datetime import now_utc


@dataclass(frozen=True)
class HealthSnapshot:
    status: str
    app: str
    environment: str
    checked_at: datetime


_snapshot: HealthSnapshot | None = None


def current_health_status() -> str:
    return "ok"


def get_health_snapshot(settings: Settings) -> HealthSnapshot:
    global _snapshot
    status = current_health_status()
    if (
        _snapshot is None
        or _snapshot.status != status
        or _snapshot.app != settings.app_name
        or _snapshot.environment != settings.app_env
    ):
        _snapshot = HealthSnapshot(
            status=status,
            app=settings.app_name,
            environment=settings.app_env,
            checked_at=now_utc(),
        )
    return _snapshot