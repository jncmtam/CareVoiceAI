from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_principal
from app.core.config import Settings, get_settings
from app.core.errors import APIError
from app.db.session import get_db
from app.integrations.vnpt import vnpt_gateway
from app.schemas.checkins import (
    CheckinAudioStatusResponse,
    CheckinHistoryResponse,
    CheckinJobResponse,
    SubmitCheckinResponse,
    TodayCheckinResponse,
)
from app.services.auth import Principal
from app.services.checkins import CheckinService

router = APIRouter()


@router.get("/me/checkins/today", response_model=TodayCheckinResponse)
async def today_checkin(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> TodayCheckinResponse:
    response = await CheckinService(db, settings, vnpt_gateway).today(principal)
    await db.commit()
    return response


@router.get("/checkins/{checkin_id}/audio", response_model=CheckinAudioStatusResponse)
async def checkin_audio(
    checkin_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> CheckinAudioStatusResponse:
    response = await CheckinService(db, settings, vnpt_gateway).audio_status(checkin_id, principal)
    await db.commit()
    return response


@router.post(
    "/checkins/{checkin_id}/responses",
    response_model=SubmitCheckinResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def submit_checkin(
    checkin_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    audio_file: Annotated[UploadFile | None, File()] = None,
    quick_answer_id: Annotated[str | None, Form()] = None,
    recorded_duration_seconds: Annotated[int | None, Form()] = None,
    client_recorded_at: Annotated[str | None, Form()] = None,
    client_request_id: Annotated[str, Form()] = "",
) -> SubmitCheckinResponse:
    if not client_request_id:
        raise APIError("invalid_request", "client_request_id là bắt buộc.", 400)
    parsed_recorded_at = _parse_datetime(client_recorded_at) if client_recorded_at else None
    response = await CheckinService(db, settings, vnpt_gateway).submit_response(
        checkin_id=checkin_id,
        audio_file=audio_file,
        quick_answer_id=quick_answer_id,
        recorded_duration_seconds=recorded_duration_seconds,
        client_recorded_at=parsed_recorded_at,
        client_request_id=client_request_id,
        principal=principal,
    )
    await db.commit()
    return response


@router.get("/checkin_jobs/{job_id}", response_model=CheckinJobResponse)
async def checkin_job(
    job_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> CheckinJobResponse:
    return await CheckinService(db, settings, vnpt_gateway).job(job_id, principal)


@router.get("/me/checkins/history", response_model=CheckinHistoryResponse)
async def checkin_history(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    limit: int = 30,
    cursor: str | None = None,
) -> CheckinHistoryResponse:
    _ = cursor
    return await CheckinService(db, settings, vnpt_gateway).history(
        principal, limit=min(max(limit, 1), 100)
    )


def _parse_datetime(value: str) -> datetime:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise APIError("invalid_request", "client_recorded_at không đúng ISO 8601.", 400) from exc

