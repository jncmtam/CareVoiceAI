from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_principal, vnpt_gateway_dep
from app.core.config import Settings, get_settings
from app.core.errors import APIError
from app.db.session import get_db
from app.integrations.vnpt import VNPTGateway
from app.models.enums import RiskLevel
from app.schemas.checkins import (
    CheckinAudioStatusResponse,
    CheckinHistoryResponse,
    CheckinJobResponse,
    CheckinTranscribeResponse,
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
    gateway: Annotated[VNPTGateway, Depends(vnpt_gateway_dep)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> TodayCheckinResponse:
    response = await CheckinService(db, settings, gateway).today(principal)
    await db.commit()
    return response


@router.get("/checkins/{checkin_id}/audio", response_model=CheckinAudioStatusResponse)
async def checkin_audio(
    checkin_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    gateway: Annotated[VNPTGateway, Depends(vnpt_gateway_dep)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> CheckinAudioStatusResponse:
    response = await CheckinService(db, settings, gateway).audio_status(checkin_id, principal)
    await db.commit()
    return response


@router.post("/checkins/{checkin_id}/transcribe", response_model=CheckinTranscribeResponse)
async def transcribe_checkin_audio(
    checkin_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    gateway: Annotated[VNPTGateway, Depends(vnpt_gateway_dep)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    audio_file: Annotated[UploadFile, File()],
    recorded_duration_seconds: Annotated[int | None, Form()] = None,
) -> CheckinTranscribeResponse:
    response = await CheckinService(db, settings, gateway).transcribe_preview(
        checkin_id=checkin_id,
        audio_file=audio_file,
        recorded_duration_seconds=recorded_duration_seconds,
        principal=principal,
    )
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
    gateway: Annotated[VNPTGateway, Depends(vnpt_gateway_dep)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    audio_file: Annotated[UploadFile | None, File()] = None,
    quick_answer_id: Annotated[str | None, Form()] = None,
    confirmed_transcript: Annotated[str | None, Form()] = None,
    patient_declared_risk_level: Annotated[str | None, Form()] = None,
    recorded_duration_seconds: Annotated[int | None, Form()] = None,
    client_recorded_at: Annotated[str | None, Form()] = None,
    client_request_id: Annotated[str, Form()] = "",
) -> SubmitCheckinResponse:
    if not client_request_id:
        raise APIError("invalid_request", "client_request_id là bắt buộc.", 400)
    parsed_recorded_at = _parse_datetime(client_recorded_at) if client_recorded_at else None
    declared_level = _parse_risk_level(patient_declared_risk_level)
    response = await CheckinService(db, settings, gateway).submit_response(
        checkin_id=checkin_id,
        audio_file=audio_file,
        quick_answer_id=quick_answer_id,
        confirmed_transcript=confirmed_transcript,
        patient_declared_risk_level=declared_level,
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
    gateway: Annotated[VNPTGateway, Depends(vnpt_gateway_dep)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> CheckinJobResponse:
    return await CheckinService(db, settings, gateway).job(job_id, principal)


@router.get("/me/checkins/history", response_model=CheckinHistoryResponse)
async def checkin_history(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    gateway: Annotated[VNPTGateway, Depends(vnpt_gateway_dep)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    limit: int = 30,
    cursor: str | None = None,
) -> CheckinHistoryResponse:
    _ = cursor
    return await CheckinService(db, settings, gateway).history(
        principal, limit=min(max(limit, 1), 100)
    )


def _parse_risk_level(value: str | None) -> RiskLevel | None:
    if not value:
        return None
    try:
        return RiskLevel(value)
    except ValueError as exc:
        raise APIError(
            "invalid_request",
            "patient_declared_risk_level phải là normal, attention hoặc intervention.",
            400,
        ) from exc


def _parse_datetime(value: str) -> datetime:
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise APIError("invalid_request", "client_recorded_at không đúng ISO 8601.", 400) from exc

