from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.config import Settings, get_settings
from app.schemas.common import HealthResponse
from app.services.health_state import get_health_snapshot

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
async def health(settings: Annotated[Settings, Depends(get_settings)]) -> HealthResponse:
    snapshot = get_health_snapshot(settings)
    return HealthResponse(
        status=snapshot.status,
        app=snapshot.app,
        environment=snapshot.environment,
        checked_at=snapshot.checked_at,
    )
