from datetime import timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import APIError
from app.models import FaceVerificationSession, Patient
from app.schemas.devices import (
    FaceVerificationSessionRequest,
    FaceVerificationSessionResponse,
    FaceVerificationStatusResponse,
)
from app.services.auth import Principal
from app.utils.datetime import now_utc
from app.utils.ids import new_id


class IdentityService:
    def __init__(self, session: AsyncSession, settings: Settings) -> None:
        self.session = session
        self.settings = settings

    async def create_session(
        self, request: FaceVerificationSessionRequest, principal: Principal
    ) -> FaceVerificationSessionResponse:
        if not principal.is_staff and principal.patient_id != request.patient_id:
            raise APIError("forbidden", "Bạn không có quyền tạo phiên xác thực này.", 403)
        patient = await self.session.get(Patient, request.patient_id)
        if not patient:
            raise APIError("not_found", "Không tìm thấy bệnh nhân.", 404)
        session = FaceVerificationSession(
            id=new_id("face"),
            patient_id=request.patient_id,
            requested_by_user_id=principal.user_id,
            purpose=request.purpose,
            status="not_started",
            upload_url=None,
            expires_at=now_utc() + timedelta(minutes=30),
            needs_staff_review=False,
        )
        session.upload_url = (
            f"{str(self.settings.media_base_url).rstrip('/')}"
            f"/identity/face_verification/sessions/{session.id}/upload"
        )
        self.session.add(session)
        return FaceVerificationSessionResponse(
            session_id=session.id,
            status=session.status,
            upload_url=session.upload_url,
            expires_at=session.expires_at,
        )

    async def status(
        self, session_id: str, principal: Principal
    ) -> FaceVerificationStatusResponse:
        session = await self.session.get(FaceVerificationSession, session_id)
        if not session:
            raise APIError("not_found", "Không tìm thấy phiên xác thực.", 404)
        if not principal.is_staff and principal.patient_id != session.patient_id:
            raise APIError("forbidden", "Bạn không có quyền xem phiên xác thực này.", 403)
        if session.status == "not_started" and session.expires_at and session.expires_at < now_utc():
            session.status = "expired"
            session.needs_staff_review = True
        return FaceVerificationStatusResponse(
            session_id=session.id,
            status=session.status,
            verified_at=session.verified_at,
            needs_staff_review=session.needs_staff_review,
        )

