from typing import Annotated

from fastapi import APIRouter, Depends, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.datastructures import UploadFile as StarletteUploadFile

from app.api.deps import get_current_principal
from app.core.config import Settings, get_settings
from app.core.errors import APIError
from app.db.session import get_db
from app.integrations.vnpt import vnpt_gateway
from app.schemas.hotline import (
    HotlineHistoryResponse,
    HotlineQuestionResponse,
    HotlineQuestionStatusResponse,
    HotlineQuestionTextRequest,
)
from app.services.auth import Principal
from app.services.hotline import HotlineService

router = APIRouter()


@router.post("/hotline/questions", response_model=HotlineQuestionResponse)
async def ask_hotline(
    request: Request,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> HotlineQuestionResponse | JSONResponse:
    service = HotlineService(db, settings, vnpt_gateway)
    content_type = request.headers.get("content-type", "")
    if "multipart/form-data" in content_type:
        form = await request.form()
        mode = str(form.get("mode") or "")
        if mode != "voice":
            raise APIError("invalid_request", "mode multipart phải là voice.", 400)
        audio = form.get("audio_file")
        if not isinstance(audio, StarletteUploadFile):
            raise APIError("invalid_request", "audio_file là bắt buộc.", 400)
        client_request_id = str(form.get("client_request_id") or "")
        if not client_request_id:
            raise APIError("invalid_request", "client_request_id là bắt buộc.", 400)
        duration = form.get("recorded_duration_seconds")
        response = await service.ask_voice(
            patient_id=str(form.get("patient_id")) if form.get("patient_id") else None,
            audio_file=audio,
            recorded_duration_seconds=int(duration) if duration else None,
            client_request_id=client_request_id,
            principal=principal,
        )
        await db.commit()
        return JSONResponse(
            status_code=status.HTTP_202_ACCEPTED,
            content=jsonable_encoder(response),
        )

    try:
        body = HotlineQuestionTextRequest.model_validate(await request.json())
    except (ValidationError, ValueError) as exc:
        raise APIError("validation_error", "Dữ liệu câu hỏi không hợp lệ.", 422) from exc
    response = await service.ask_text(
        patient_id=body.patient_id,
        text=body.text,
        client_request_id=body.client_request_id,
        principal=principal,
    )
    await db.commit()
    return response


@router.get("/hotline/questions/{question_id}", response_model=HotlineQuestionStatusResponse)
async def hotline_status(
    question_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> HotlineQuestionStatusResponse:
    return await HotlineService(db, settings, vnpt_gateway).status(question_id, principal)


@router.get("/hotline/questions", response_model=HotlineHistoryResponse)
async def hotline_history(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    patient_id: str | None = None,
    limit: int = 30,
    cursor: str | None = None,
) -> HotlineHistoryResponse:
    _ = cursor
    return await HotlineService(db, settings, vnpt_gateway).history(
        patient_id=patient_id,
        principal=principal,
        limit=min(max(limit, 1), 100),
    )

