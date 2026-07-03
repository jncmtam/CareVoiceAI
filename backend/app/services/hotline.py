from fastapi import UploadFile
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import APIError
from app.integrations.vnpt import VNPTGateway
from app.models import HotlineQuestion, Job, Medication, Patient, StaffAlert
from app.models.enums import HandlingStatus, JobStatus, JobType, RiskLevel, TimelineEntryType
from app.schemas.hotline import (
    HotlineHistoryItem,
    HotlineHistoryResponse,
    HotlineQuestionResponse,
    HotlineQuestionStatusResponse,
)
from app.services.auth import Principal
from app.services.idempotency import IdempotencyService, request_hash
from app.services.storage import StorageService
from app.utils.datetime import now_utc
from app.utils.ids import new_id


class HotlineService:
    def __init__(self, session: AsyncSession, settings: Settings, gateway: VNPTGateway) -> None:
        self.session = session
        self.settings = settings
        self.gateway = gateway
        self.storage = StorageService(settings)
        self.idempotency = IdempotencyService(session)

    async def ask_text(
        self,
        *,
        patient_id: str | None,
        text: str,
        client_request_id: str,
        principal: Principal,
    ) -> HotlineQuestionResponse:
        resolved_patient_id = await self._resolve_patient_id(patient_id, principal)
        payload_hash = request_hash(
            {"patient_id": resolved_patient_id, "mode": "text", "text": text}
        )
        replay = await self._replay(
            principal=principal, client_request_id=client_request_id, payload_hash=payload_hash
        )
        if replay:
            return HotlineQuestionResponse.model_validate(replay)
        question = HotlineQuestion(
            id=new_id("hot"),
            patient_id=resolved_patient_id,
            asked_by_user_id=principal.user_id,
            mode="text",
            question_text=text,
            client_request_id=client_request_id,
            status=JobStatus.processing,
        )
        self.session.add(question)
        await self._answer_question(question=question, text=text)
        response = HotlineQuestionResponse(
            question_id=question.id,
            job_id=question.job_id,
            status=question.status,
            answer_text=question.answer_text,
            source_scope=question.source_scope,
            needs_staff_review=question.needs_staff_review,
            staff_alert_id=question.staff_alert_id,
            poll_after_seconds=None,
        )
        await self._store(
            principal=principal,
            client_request_id=client_request_id,
            payload_hash=payload_hash,
            response=response.model_dump(mode="json"),
        )
        return response

    async def ask_voice(
        self,
        *,
        patient_id: str | None,
        audio_file: UploadFile,
        recorded_duration_seconds: int | None,
        client_request_id: str,
        principal: Principal,
    ) -> HotlineQuestionResponse:
        resolved_patient_id = await self._resolve_patient_id(patient_id, principal)
        payload_hash = request_hash(
            {
                "patient_id": resolved_patient_id,
                "mode": "voice",
                "filename": audio_file.filename,
                "duration": recorded_duration_seconds,
            }
        )
        replay = await self._replay(
            principal=principal, client_request_id=client_request_id, payload_hash=payload_hash
        )
        if replay:
            return HotlineQuestionResponse.model_validate(replay)
        audio_url, _ = await self.storage.save_upload(
            audio_file, folder=f"patients/{resolved_patient_id}/hotline"
        )
        question = HotlineQuestion(
            id=new_id("hot"),
            patient_id=resolved_patient_id,
            asked_by_user_id=principal.user_id,
            mode="voice",
            audio_url=audio_url,
            recorded_duration_seconds=recorded_duration_seconds,
            client_request_id=client_request_id,
            status=JobStatus.transcribing,
        )
        job = Job(
            id=new_id("hotline_job"),
            job_type=JobType.hotline,
            status=JobStatus.transcribing,
            progress=50,
            stage="transcribing",
            poll_after_seconds=2,
            patient_id=resolved_patient_id,
            source_id=question.id,
        )
        question.job_id = job.id
        self.session.add_all([question, job])
        speech = await self.gateway.transcribe_audio(file_url=audio_url, fallback_text=None)
        question.transcript = speech.transcript
        await self._answer_question(question=question, text=speech.transcript)
        job.status = JobStatus.completed
        job.progress = 100
        job.stage = "completed"
        job.poll_after_seconds = None
        job.completed_at = now_utc()
        response = HotlineQuestionResponse(
            question_id=question.id,
            job_id=job.id,
            status=JobStatus.transcribing,
            poll_after_seconds=2,
        )
        await self._store(
            principal=principal,
            client_request_id=client_request_id,
            payload_hash=payload_hash,
            response=response.model_dump(mode="json"),
        )
        return response

    async def status(self, question_id: str, principal: Principal) -> HotlineQuestionStatusResponse:
        question = await self.session.get(HotlineQuestion, question_id)
        if not question:
            raise APIError("not_found", "Không tìm thấy câu hỏi hotline.", 404)
        if not principal.is_staff and principal.patient_id != question.patient_id:
            raise APIError("forbidden", "Bạn không có quyền xem câu hỏi này.", 403)
        return HotlineQuestionStatusResponse(
            question_id=question.id,
            status=question.status,
            transcript=question.transcript,
            answer_text=question.answer_text,
            needs_staff_review=question.needs_staff_review,
            risk_level=question.risk_level,
            staff_alert_id=question.staff_alert_id,
            poll_after_seconds=None if question.status == JobStatus.completed else 2,
        )

    async def history(
        self, *, patient_id: str | None, principal: Principal, limit: int
    ) -> HotlineHistoryResponse:
        resolved_patient_id = await self._resolve_patient_id(patient_id, principal)
        result = await self.session.execute(
            select(HotlineQuestion)
            .where(
                HotlineQuestion.patient_id == resolved_patient_id,
                HotlineQuestion.deleted_at.is_(None),
            )
            .order_by(HotlineQuestion.created_at.desc())
            .limit(limit)
        )
        return HotlineHistoryResponse(
            items=[
                HotlineHistoryItem(
                    question_id=item.id,
                    asked_at=item.created_at,
                    question_text=item.question_text or item.transcript,
                    answer_text=item.answer_text,
                    needs_staff_review=item.needs_staff_review,
                )
                for item in result.scalars()
            ],
            next_cursor=None,
        )

    async def _answer_question(self, *, question: HotlineQuestion, text: str) -> None:
        has_record = await self._has_confirmed_medication(question.patient_id)
        answer = await self.gateway.answer_hotline(text=text, has_confirmed_record=has_record)
        risk_level = RiskLevel(answer["risk_level"])
        question.question_text = question.question_text or text
        question.answer_text = answer["answer_text"]
        question.source_scope = answer["source_scope"]
        question.needs_staff_review = bool(answer["needs_staff_review"])
        question.risk_level = risk_level
        question.status = JobStatus.completed
        patient = await self.session.get(Patient, question.patient_id)
        if patient and risk_level != RiskLevel.normal:
            patient.latest_risk_level = risk_level
        if question.needs_staff_review:
            alert = StaffAlert(
                id=new_id("alert"),
                patient_id=question.patient_id,
                source_type=TimelineEntryType.hotline_question,
                source_id=question.id,
                risk_level=risk_level,
                summary=question.answer_text,
                handling_status=HandlingStatus.new,
                unread=True,
            )
            self.session.add(alert)
            question.staff_alert_id = alert.id

    async def _has_confirmed_medication(self, patient_id: str) -> bool:
        result = await self.session.execute(
            select(func.count(Medication.id)).where(
                Medication.patient_id == patient_id,
                Medication.deleted_at.is_(None),
                Medication.is_active.is_(True),
            )
        )
        return int(result.scalar_one()) > 0

    async def _resolve_patient_id(self, patient_id: str | None, principal: Principal) -> str:
        if principal.is_staff:
            if not patient_id:
                raise APIError("invalid_request", "patient_id là bắt buộc với staff.", 400)
            patient = await self.session.get(Patient, patient_id)
            if not patient:
                raise APIError("not_found", "Không tìm thấy bệnh nhân.", 404)
            return patient_id
        if not principal.patient_id:
            raise APIError("forbidden", "Tài khoản không gắn với bệnh nhân.", 403)
        if patient_id and patient_id != principal.patient_id:
            raise APIError("forbidden", "Bạn không có quyền hỏi thay bệnh nhân này.", 403)
        return principal.patient_id

    async def _replay(
        self, *, principal: Principal, client_request_id: str, payload_hash: str
    ) -> dict | None:
        replay = await self.idempotency.get_replay(
            scope="hotline_question",
            actor_id=principal.user_id,
            client_request_id=client_request_id,
            request_hash_value=payload_hash,
        )
        if replay and replay.get("_conflict"):
            raise APIError("conflict", replay["error"], 409)
        return replay

    async def _store(
        self,
        *,
        principal: Principal,
        client_request_id: str,
        payload_hash: str,
        response: dict,
    ) -> None:
        await self.idempotency.store(
            scope="hotline_question",
            actor_id=principal.user_id,
            client_request_id=client_request_id,
            request_hash_value=payload_hash,
            response_status=200,
            response_body=response,
        )

