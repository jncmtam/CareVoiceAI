import hashlib
from pathlib import Path

from fastapi import UploadFile
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.errors import APIError
from app.db.session import AsyncSessionLocal
from app.integrations.vnpt import VNPTGateway, get_vnpt_gateway
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
from app.services.job_runner import job_runner
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
            status=JobStatus.needs_review,
        )
        self.session.add(question)
        await self._queue_text_for_staff(question=question, text=text)
        response = self._build_response(question=question)
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
        audio_bytes = await audio_file.read()
        if not audio_bytes:
            raise APIError("invalid_request", "audio_file rỗng.", 400)
        filename = audio_file.filename or "recording.m4a"
        content_type = audio_file.content_type or "audio/m4a"
        payload_hash = request_hash(
            {
                "patient_id": resolved_patient_id,
                "mode": "voice",
                "audio_sha256": hashlib.sha256(audio_bytes).hexdigest(),
            }
        )
        replay = await self._replay(
            principal=principal, client_request_id=client_request_id, payload_hash=payload_hash
        )
        if replay:
            return HotlineQuestionResponse.model_validate(replay)
        suffix = Path(filename).suffix.lower() or ".m4a"
        stored_name = f"{new_id('file')}{suffix}"
        audio_url = await self.storage.save_bytes(
            folder=f"patients/{resolved_patient_id}/hotline",
            filename=stored_name,
            data=audio_bytes,
            content_type=content_type,
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

        if self.settings.vendor_mock_mode:
            await self._process_voice_question(question=question, job=job)
        else:
            job_runner.enqueue(
                lambda: run_hotline_job(job.id),
                label=f"hotline:{job.id}",
                delay_seconds=self.settings.background_job_start_delay_seconds,
            )

        response_status = question.status if self.settings.vendor_mock_mode else JobStatus.transcribing
        response = self._build_response(
            question=question,
            status_override=response_status,
            poll_after_seconds=None if response_status == JobStatus.completed else 2,
        )
        await self._store(
            principal=principal,
            client_request_id=client_request_id,
            payload_hash=payload_hash,
            response=response.model_dump(mode="json"),
        )
        return response

    async def process_hotline_job(self, job_id: str) -> None:
        job = await self.session.get(Job, job_id)
        if not job or job.job_type != JobType.hotline or not job.source_id:
            return
        question = await self.session.get(HotlineQuestion, job.source_id)
        if not question:
            return
        await self._process_voice_question(question=question, job=job)

    async def _process_voice_question(self, *, question: HotlineQuestion, job: Job) -> None:
        if not question.audio_url:
            raise APIError("invalid_request", "Không tìm thấy audio cho câu hỏi hotline.", 400)
        question.status = JobStatus.transcribing
        job.status = JobStatus.transcribing
        job.progress = 40
        job.stage = "transcribing"
        job.poll_after_seconds = 2
        file_bytes, filename, content_type = await self.storage.read_bytes(question.audio_url)
        speech = await self.gateway.transcribe_audio(
            file_url=question.audio_url,
            fallback_text=None,
            file_bytes=file_bytes,
            filename=filename,
            content_type=content_type,
            duration_seconds=question.recorded_duration_seconds,
        )
        question.transcript = speech.transcript
        question.status = JobStatus.processing
        job.status = JobStatus.processing
        job.progress = 75
        job.stage = "classifying"
        await self._complete_voice_symptoms(question=question, text=speech.transcript)
        job.status = JobStatus.completed
        job.progress = 100
        job.stage = "completed"
        job.poll_after_seconds = None
        job.completed_at = now_utc()

    async def status(self, question_id: str, principal: Principal) -> HotlineQuestionStatusResponse:
        question = await self.session.get(HotlineQuestion, question_id)
        if not question:
            raise APIError("not_found", "Không tìm thấy câu hỏi hotline.", 404)
        if not principal.is_staff and principal.patient_id != question.patient_id:
            raise APIError("forbidden", "Bạn không có quyền xem câu hỏi này.", 403)
        return HotlineQuestionStatusResponse(
            question_id=question.id,
            status=question.status,
            transcript=question.transcript or question.question_text,
            answer_text=question.answer_text,
            needs_staff_review=question.needs_staff_review,
            risk_level=question.risk_level,
            reasons=question.risk_reasons,
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
                    mode=item.mode,
                    question_text=item.question_text,
                    transcript=item.transcript,
                    answer_text=item.answer_text,
                    needs_staff_review=item.needs_staff_review,
                    risk_level=item.risk_level,
                    reasons=item.risk_reasons,
                )
                for item in result.scalars()
            ],
            next_cursor=None,
        )

    async def _queue_text_for_staff(self, *, question: HotlineQuestion, text: str) -> None:
        level, reasons = self._classify_symptoms(text)
        question.question_text = text
        question.transcript = text
        question.answer_text = None
        question.source_scope = "staff_manual"
        question.needs_staff_review = True
        question.risk_level = level
        question.risk_reasons = reasons
        question.status = JobStatus.needs_review
        patient = await self.session.get(Patient, question.patient_id)
        if patient:
            patient.latest_risk_level = max(
                [patient.latest_risk_level or RiskLevel.normal, level],
                key=self._risk_priority,
            )
        await self._maybe_create_staff_alert(
            question=question,
            summary=text,
            risk_level=level,
        )

    async def _complete_voice_symptoms(self, *, question: HotlineQuestion, text: str) -> None:
        level, reasons = self._classify_symptoms(text)
        question.question_text = question.question_text or text
        question.transcript = text
        question.answer_text = self._patient_summary(level)
        question.source_scope = "symptom_stt"
        question.needs_staff_review = level != RiskLevel.normal
        question.risk_level = level
        question.risk_reasons = reasons
        question.status = JobStatus.completed
        patient = await self.session.get(Patient, question.patient_id)
        if patient and level != RiskLevel.normal:
            patient.latest_risk_level = level
        if question.needs_staff_review:
            await self._maybe_create_staff_alert(
                question=question,
                summary=question.answer_text or text,
                risk_level=level,
            )

    async def _maybe_create_staff_alert(
        self,
        *,
        question: HotlineQuestion,
        summary: str,
        risk_level: RiskLevel,
    ) -> None:
        alert = StaffAlert(
            id=new_id("alert"),
            patient_id=question.patient_id,
            source_type=TimelineEntryType.hotline_question,
            source_id=question.id,
            risk_level=risk_level,
            summary=summary,
            handling_status=HandlingStatus.new,
            unread=True,
        )
        self.session.add(alert)
        question.staff_alert_id = alert.id
        from app.services.caregiver_alerts import CaregiverAlertService

        if risk_level != RiskLevel.normal:
            await CaregiverAlertService(self.session).maybe_notify(
                patient_id=question.patient_id,
                trigger_type="hotline",
                source_id=question.id,
                summary=summary,
                risk_level=risk_level,
            )

    def _classify_symptoms(self, transcript: str) -> tuple[RiskLevel, list[str]]:
        reasons = self._keyword_reasons(transcript)
        if any("đau ngực" in r or "khó thở" in r or "ngất" in r for r in reasons):
            return RiskLevel.intervention, reasons
        if reasons:
            return RiskLevel.attention, reasons
        return RiskLevel.normal, ["Không có triệu chứng cảnh báo trong phản hồi hôm nay"]

    def _keyword_reasons(self, transcript: str) -> list[str]:
        lower = transcript.lower()
        reasons: list[str] = []
        if "đau ngực" in lower:
            reasons.append("Hotline: bệnh nhân báo đau ngực")
        if "khó thở" in lower:
            reasons.append("Hotline: bệnh nhân báo khó thở")
        if "ngất" in lower:
            reasons.append("Hotline: bệnh nhân báo ngất hoặc choáng")
        if "chóng mặt" in lower:
            reasons.append("Hotline: bệnh nhân báo chóng mặt")
        if "mệt" in lower:
            reasons.append("Hotline: bệnh nhân báo mệt bất thường")
        if "sốt" in lower:
            reasons.append("Hotline: bệnh nhân báo sốt")
        return reasons

    def _patient_summary(self, level: RiskLevel) -> str:
        if level == RiskLevel.intervention:
            return "Bệnh nhân báo triệu chứng cảnh báo, cần nhân viên y tế gọi lại sớm."
        if level == RiskLevel.attention:
            return "Bệnh nhân có dấu hiệu cần theo dõi, điều dưỡng sẽ xem lại phản hồi."
        return "Tình trạng ổn định theo phản hồi của bác."

    def _risk_priority(self, level: RiskLevel) -> int:
        return {
            RiskLevel.intervention: 3,
            RiskLevel.attention: 2,
            RiskLevel.normal: 1,
        }[level]

    def _build_response(
        self,
        *,
        question: HotlineQuestion,
        status_override: JobStatus | None = None,
        poll_after_seconds: float | None = None,
    ) -> HotlineQuestionResponse:
        status = status_override or question.status
        completed = status in {JobStatus.completed, JobStatus.needs_review}
        return HotlineQuestionResponse(
            question_id=question.id,
            job_id=question.job_id,
            status=status,
            transcript=question.transcript or question.question_text,
            answer_text=question.answer_text if completed else None,
            source_scope=question.source_scope if completed else None,
            needs_staff_review=question.needs_staff_review if completed else None,
            risk_level=question.risk_level if completed else None,
            reasons=question.risk_reasons if completed else None,
            staff_alert_id=question.staff_alert_id if completed else None,
            poll_after_seconds=poll_after_seconds,
        )

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
            # Voice uploads may finalize on device after the first byte read.
            # Reuse the stored response instead of failing with 409.
            stored = await self.idempotency.repo.get_key(
                scope="hotline_question",
                actor_id=principal.user_id,
                client_request_id=client_request_id,
            )
            if stored:
                return stored.response_body
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


async def run_hotline_job(job_id: str) -> None:
    settings = get_settings()
    async with AsyncSessionLocal() as session:
        service = HotlineService(session, settings, get_vnpt_gateway(settings))
        try:
            await service.process_hotline_job(job_id)
            await session.commit()
        except Exception as exc:
            await session.rollback()
            async with AsyncSessionLocal() as fail_session:
                job = await fail_session.get(Job, job_id)
                if job:
                    job.status = JobStatus.failed
                    job.stage = "failed"
                    job.error_code = "vendor_unavailable"
                    job.error_message = str(exc)
                    job.poll_after_seconds = None
                    if job.source_id:
                        question = await fail_session.get(HotlineQuestion, job.source_id)
                        if question:
                            question.status = JobStatus.failed
                    await fail_session.commit()
            raise