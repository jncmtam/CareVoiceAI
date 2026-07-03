from datetime import date, datetime, time

from fastapi import UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import APIError
from app.integrations.vnpt import VNPTGateway
from app.models import Checkin, CheckinResponse, Job, Patient, StaffAlert
from app.models.enums import AudioStatus, HandlingStatus, JobStatus, JobType, RiskLevel, TimelineEntryType
from app.schemas.checkins import (
    Checkin as CheckinSchema,
)
from app.schemas.checkins import (
    CheckinAudioStatusResponse,
    CheckinHistoryItem,
    CheckinHistoryResponse,
    CheckinJobResponse,
    QuickAnswer,
    RiskAssessment,
    SubmitCheckinResponse,
    TodayCheckinResponse,
)
from app.services.auth import Principal
from app.services.idempotency import IdempotencyService, request_hash
from app.services.storage import StorageService
from app.utils.datetime import now_utc
from app.utils.ids import new_id


class CheckinService:
    def __init__(self, session: AsyncSession, settings: Settings, gateway: VNPTGateway) -> None:
        self.session = session
        self.settings = settings
        self.gateway = gateway
        self.storage = StorageService(settings)
        self.idempotency = IdempotencyService(session)

    async def today(self, principal: Principal) -> TodayCheckinResponse:
        if not principal.patient_id:
            raise APIError("forbidden", "Chỉ bệnh nhân/người nhà có check-in cá nhân.", 403)
        checkin = await self._get_or_create_today_checkin(principal.patient_id)
        return TodayCheckinResponse(checkin=self._checkin_schema(checkin))

    async def audio_status(self, checkin_id: str, principal: Principal) -> CheckinAudioStatusResponse:
        checkin = await self.session.get(Checkin, checkin_id)
        if not checkin:
            raise APIError("not_found", "Không tìm thấy check-in.", 404)
        if not principal.is_staff and principal.patient_id != checkin.patient_id:
            raise APIError("forbidden", "Bạn không có quyền xem check-in này.", 403)
        if checkin.audio_status == AudioStatus.generating:
            result = await self.gateway.synthesize_question(
                text=checkin.question_text,
                checkin_id=checkin.id,
                media_base_url=str(self.settings.media_base_url),
            )
            checkin.audio_status = AudioStatus.ready
            checkin.audio_url = result.audio_url
            checkin.audio_cache_key = result.audio_cache_key
        return CheckinAudioStatusResponse(
            checkin_id=checkin.id,
            audio_status=checkin.audio_status,
            audio_url=checkin.audio_url,
            audio_cache_key=checkin.audio_cache_key,
            poll_after_seconds=None if checkin.audio_status == AudioStatus.ready else 2,
        )

    async def submit_response(
        self,
        *,
        checkin_id: str,
        audio_file: UploadFile | None,
        quick_answer_id: str | None,
        recorded_duration_seconds: int | None,
        client_recorded_at: datetime | None,
        client_request_id: str,
        principal: Principal,
    ) -> SubmitCheckinResponse:
        checkin = await self.session.get(Checkin, checkin_id)
        if not checkin:
            raise APIError("not_found", "Không tìm thấy check-in.", 404)
        if not principal.is_staff and principal.patient_id != checkin.patient_id:
            raise APIError("forbidden", "Bạn không có quyền gửi check-in này.", 403)
        if not audio_file and not quick_answer_id:
            raise APIError("invalid_request", "Cần audio_file hoặc quick_answer_id.", 400)

        payload_hash = request_hash(
            {
                "checkin_id": checkin_id,
                "quick_answer_id": quick_answer_id,
                "duration": recorded_duration_seconds,
                "filename": audio_file.filename if audio_file else None,
            }
        )
        replay = await self.idempotency.get_replay(
            scope="checkin_response",
            actor_id=principal.user_id,
            client_request_id=client_request_id,
            request_hash_value=payload_hash,
        )
        if replay:
            if replay.get("_conflict"):
                raise APIError("conflict", replay["error"], 409)
            return SubmitCheckinResponse.model_validate(replay)

        audio_url = None
        if audio_file:
            audio_url, _ = await self.storage.save_upload(
                audio_file, folder=f"patients/{checkin.patient_id}/checkins/{checkin.id}"
            )

        response = CheckinResponse(
            id=new_id("resp"),
            checkin_id=checkin.id,
            patient_id=checkin.patient_id,
            quick_answer_id=quick_answer_id,
            audio_url=audio_url,
            recorded_duration_seconds=recorded_duration_seconds,
            client_recorded_at=client_recorded_at,
            client_request_id=client_request_id,
            status=JobStatus.analyzing,
        )
        job = Job(
            id=new_id("checkin_job"),
            job_type=JobType.checkin_analysis,
            status=JobStatus.analyzing,
            progress=50,
            stage="risk_classification",
            poll_after_seconds=2,
            patient_id=checkin.patient_id,
            source_id=response.id,
        )
        response.job_id = job.id
        self.session.add_all([response, job])
        await self._process_response(response=response, job=job)
        api_response = SubmitCheckinResponse(
            response_id=response.id,
            job_id=job.id,
            status=JobStatus.queued,
            poll_after_seconds=2,
            message="Đã nhận câu trả lời. Hệ thống đang gửi điều dưỡng xem lại nếu cần.",
        )
        await self.idempotency.store(
            scope="checkin_response",
            actor_id=principal.user_id,
            client_request_id=client_request_id,
            request_hash_value=payload_hash,
            response_status=202,
            response_body=api_response.model_dump(mode="json"),
        )
        return api_response

    async def job(self, job_id: str, principal: Principal) -> CheckinJobResponse:
        job = await self.session.get(Job, job_id)
        if not job or job.job_type != JobType.checkin_analysis:
            raise APIError("not_found", "Không tìm thấy check-in job.", 404)
        if not principal.is_staff and principal.patient_id != job.patient_id:
            raise APIError("forbidden", "Bạn không có quyền xem job này.", 403)
        response = await self.session.get(CheckinResponse, job.source_id) if job.source_id else None
        risk = None
        if response and response.risk_level:
            risk = RiskAssessment(
                level=response.risk_level,
                label=self._risk_label(response.risk_level),
                reasons=response.risk_reasons,
                needs_staff_review=response.needs_staff_review,
            )
        return CheckinJobResponse(
            job_id=job.id,
            response_id=response.id if response else job.source_id,
            status=job.status,
            progress=job.progress,
            stage=job.stage,
            display_message="Đang phân tích phản hồi..." if job.status != JobStatus.completed else "Đã phân tích xong.",
            poll_after_seconds=job.poll_after_seconds,
            transcript=response.transcript if response else None,
            summary=response.summary if response else None,
            risk=risk,
            staff_alert_id=response.staff_alert_id if response else None,
            completed_at=job.completed_at,
        )

    async def history(self, principal: Principal, limit: int) -> CheckinHistoryResponse:
        if not principal.patient_id:
            raise APIError("forbidden", "Chỉ bệnh nhân/người nhà có lịch sử check-in cá nhân.", 403)
        result = await self.session.execute(
            select(CheckinResponse)
            .where(
                CheckinResponse.patient_id == principal.patient_id,
                CheckinResponse.deleted_at.is_(None),
            )
            .order_by(CheckinResponse.created_at.desc())
            .limit(limit)
        )
        items = [
            CheckinHistoryItem(
                id=item.id,
                checked_in_at=item.created_at,
                status="reviewed" if item.handling_status else "completed",
                risk_level=item.risk_level,
                patient_message="Điều dưỡng đã xem" if item.handling_status else "Bác đã gửi phản hồi hôm nay.",
                summary_for_patient="Bác đã gửi phản hồi hôm nay.",
            )
            for item in result.scalars()
        ]
        return CheckinHistoryResponse(items=items, next_cursor=None)

    async def _get_or_create_today_checkin(self, patient_id: str) -> Checkin:
        today = date.today()
        result = await self.session.execute(
            select(Checkin).where(Checkin.patient_id == patient_id, Checkin.scheduled_for == today)
        )
        checkin = result.scalar_one_or_none()
        if checkin:
            return checkin
        expires_at = datetime.combine(today, time(23, 59, 59)).replace(tzinfo=now_utc().tzinfo)
        checkin = Checkin(
            id=new_id("chk"),
            patient_id=patient_id,
            scheduled_for=today,
            status="ready",
            question_text="Hôm nay bác có thấy mệt, khó thở hoặc đau ngực không?",
            audio_status=AudioStatus.unavailable,
            expires_at=expires_at,
        )
        self.session.add(checkin)
        return checkin

    def _checkin_schema(self, checkin: Checkin) -> CheckinSchema:
        return CheckinSchema(
            id=checkin.id,
            patient_id=checkin.patient_id,
            scheduled_for=checkin.scheduled_for,
            status=checkin.status,
            question_text=checkin.question_text,
            audio_status=checkin.audio_status,
            audio_url=checkin.audio_url,
            audio_cache_key=checkin.audio_cache_key,
            tts_job_id=checkin.tts_job_id,
            poll_after_seconds=2 if checkin.audio_status == AudioStatus.generating else None,
            quick_answers=[
                QuickAnswer(id="yes", label="Có"),
                QuickAnswer(id="no", label="Không"),
                QuickAnswer(id="normal", label="Bình thường"),
            ],
            expires_at=checkin.expires_at,
        )

    async def _process_response(self, *, response: CheckinResponse, job: Job) -> None:
        speech = await self.gateway.transcribe_audio(
            file_url=response.audio_url,
            fallback_text=self._quick_answer_text(response.quick_answer_id),
        )
        level, reasons = self._classify_risk(speech.transcript, response.quick_answer_id)
        summary = self._summary_for(level, speech.transcript)
        response.transcript = speech.transcript
        response.summary = summary
        response.risk_level = level
        response.risk_reasons = reasons
        response.needs_staff_review = level != RiskLevel.normal
        response.status = JobStatus.completed
        response.handling_status = HandlingStatus.new if response.needs_staff_review else HandlingStatus.resolved
        job.status = JobStatus.completed
        job.progress = 100
        job.stage = "completed"
        job.poll_after_seconds = None
        job.completed_at = now_utc()
        patient = await self.session.get(Patient, response.patient_id)
        if patient:
            patient.latest_risk_level = level
            patient.latest_checkin_at = now_utc()
        if response.needs_staff_review:
            alert = StaffAlert(
                id=new_id("alert"),
                patient_id=response.patient_id,
                source_type=TimelineEntryType.checkin_response,
                source_id=response.id,
                risk_level=level,
                summary=summary,
                handling_status=HandlingStatus.new,
                unread=True,
            )
            self.session.add(alert)
            response.staff_alert_id = alert.id

    def _quick_answer_text(self, quick_answer_id: str | None) -> str | None:
        return {
            "yes": "Có triệu chứng bất thường hôm nay.",
            "no": "Không có triệu chứng bất thường hôm nay.",
            "normal": "Hôm nay tôi thấy bình thường.",
        }.get(quick_answer_id or "")

    def _classify_risk(self, transcript: str, quick_answer_id: str | None) -> tuple[RiskLevel, list[str]]:
        lower = transcript.lower()
        if any(term in lower for term in ["đau ngực", "khó thở", "ngất"]):
            return RiskLevel.intervention, ["Có triệu chứng cảnh báo cần can thiệp"]
        if quick_answer_id == "yes" or any(term in lower for term in ["chóng mặt", "mệt", "sốt"]):
            return RiskLevel.attention, ["Có triệu chứng cần theo dõi thêm"]
        return RiskLevel.normal, ["Không có triệu chứng cảnh báo"]

    def _summary_for(self, level: RiskLevel, transcript: str) -> str:
        if level == RiskLevel.intervention:
            return "Bệnh nhân báo triệu chứng cảnh báo, cần nhân viên y tế gọi lại sớm."
        if level == RiskLevel.attention:
            return "Bệnh nhân có dấu hiệu cần theo dõi, điều dưỡng nên xem lại phản hồi."
        return "Tình trạng ổn định theo phản hồi check-in."

    def _risk_label(self, level: RiskLevel) -> str:
        return {
            RiskLevel.normal: "Bình thường",
            RiskLevel.attention: "Cần chú ý",
            RiskLevel.intervention: "Cần can thiệp",
        }[level]
