from typing import Annotated

from fastapi import APIRouter, Depends, File, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_principal
from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.schemas.devices import (
    FaceVerificationSessionRequest,
    FaceVerificationSessionResponse,
    FaceVerificationStatusResponse,
    FaceVerificationUploadResponse,
)
from app.services.auth import Principal
from app.services.identity import IdentityService

router = APIRouter()


@router.post(
    "/identity/face_verification/sessions",
    response_model=FaceVerificationSessionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_face_session(
    request: FaceVerificationSessionRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> FaceVerificationSessionResponse:
    response = await IdentityService(db, settings).create_session(request, principal)
    await db.commit()
    return response


@router.get(
    "/identity/face_verification/sessions/{session_id}",
    response_model=FaceVerificationStatusResponse,
)
async def face_session_status(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> FaceVerificationStatusResponse:
    response = await IdentityService(db, settings).status(session_id, principal)
    await db.commit()
    return response


@router.post(
    "/identity/face_verification/sessions/{session_id}/upload",
    response_model=FaceVerificationUploadResponse,
)
async def upload_face_verification(
    session_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    image_file: Annotated[UploadFile, File()],
) -> FaceVerificationUploadResponse:
    response = await IdentityService(db, settings).complete_upload(
        session_id, image_file, principal
    )
    await db.commit()
    return response

