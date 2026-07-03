from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import APIError
from app.models import CheckinResponse, HotlineQuestion, Job, Patient, StaffAlert, User
from app.models.enums import HandlingStatus, JobStatus, JobType, RiskLevel, TimelineEntryType
from app.repositories.patients import PatientRepository
from app.schemas.patients import PatientSummary
from app.schemas.staff import (
    DashboardOverview,
    HandledByUser,
    HandlingUpdateRequest,
    HandlingUpdateResponse,
    PatientTimelineResponse,
    PriorityPatientListResponse,
    TimelineEntry,
    TimelinePatientHeader,
)
from app.services.auth import Principal
from app.utils.datetime import age_from_birth_date, now_utc


class StaffService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.patients = PatientRepository(session)

    async def dashboard_overview(self, principal: Principal) -> DashboardOverview:
        self._require_staff(principal)
        total = await self.patients.active_count()
        attention = await self._count_patients_by_risk(RiskLevel.attention)
        intervention = await self._count_patients_by_risk(RiskLevel.intervention)
        pending_ocr = await self._count_jobs(JobType.ocr)
        pending_analysis = await self._count_jobs(JobType.checkin_analysis)
        total_checkins = await self._count_table(CheckinResponse)
        completed_checkins = await self._count_table(
            CheckinResponse, CheckinResponse.status == JobStatus.completed
        )
        rate = completed_checkins / total_checkins if total_checkins else 0.0
        return DashboardOverview(
            total_active_patients=total,
            needs_attention_today=attention,
            needs_intervention_today=intervention,
            checkin_completion_rate=round(rate, 2),
            pending_ocr_jobs=pending_ocr,
            pending_analysis_jobs=pending_analysis,
            updated_at=now_utc(),
        )

    async def priority_patients(
        self,
        *,
        principal: Principal,
        page: int,
        per_page: int,
        query: str | None,
        risk_level: RiskLevel | None,
        handling_status: HandlingStatus | None,
    ) -> PriorityPatientListResponse:
        self._require_staff(principal)
        page = max(page, 1)
        per_page = min(max(per_page, 1), 100)
        stmt = self.patients.priority_query(query=query, risk_level=risk_level)
        if handling_status:
            stmt = stmt.join(StaffAlert, StaffAlert.patient_id == Patient.id).where(
                StaffAlert.handling_status == handling_status
            )
        count_result = await self.session.execute(
            select(func.count()).select_from(stmt.order_by(None).subquery())
        )
        total = int(count_result.scalar_one())
        result = await self.session.execute(stmt.offset((page - 1) * per_page).limit(per_page))
        patients = result.scalars().unique().all()
        items = [await self._patient_summary(patient) for patient in patients]
        return PriorityPatientListResponse(
            items=items,
            page=page,
            per_page=per_page,
            total=total,
            has_next=page * per_page < total,
        )

    async def patient_timeline(
        self, *, principal: Principal, patient_id: str, limit: int
    ) -> PatientTimelineResponse:
        self._require_staff(principal)
        patient = await self.session.get(Patient, patient_id)
        if not patient:
            raise APIError("not_found", "Không tìm thấy bệnh nhân.", 404)
        items: list[TimelineEntry] = []
        checkins = await self.session.execute(
            select(CheckinResponse)
            .where(CheckinResponse.patient_id == patient_id, CheckinResponse.deleted_at.is_(None))
            .order_by(CheckinResponse.created_at.desc())
            .limit(limit)
        )
        for response in checkins.scalars():
            items.append(
                TimelineEntry(
                    id=response.id,
                    type=TimelineEntryType.checkin_response,
                    occurred_at=response.created_at,
                    status=response.status,
                    risk_level=response.risk_level,
                    summary=response.summary,
                    transcript=response.transcript,
                    risk_reasons=response.risk_reasons,
                    handling_status=response.handling_status,
                    staff_alert_id=response.staff_alert_id,
                    display_message="Đang phân tích phản hồi..."
                    if response.status != JobStatus.completed
                    else None,
                    job_id=response.job_id,
                )
            )
        hotline = await self.session.execute(
            select(HotlineQuestion)
            .where(HotlineQuestion.patient_id == patient_id, HotlineQuestion.deleted_at.is_(None))
            .order_by(HotlineQuestion.created_at.desc())
            .limit(limit)
        )
        for question in hotline.scalars():
            items.append(
                TimelineEntry(
                    id=question.id,
                    type=TimelineEntryType.hotline_question,
                    occurred_at=question.created_at,
                    status=question.status,
                    risk_level=question.risk_level,
                    summary=question.answer_text,
                    transcript=question.transcript or question.question_text,
                    risk_reasons=None,
                    handling_status=await self._handling_for(question.staff_alert_id),
                    staff_alert_id=question.staff_alert_id,
                    display_message="Đang xử lý câu hỏi..." if question.status != JobStatus.completed else None,
                    job_id=question.job_id,
                )
            )
        items = sorted(items, key=lambda item: item.occurred_at, reverse=True)[:limit]
        return PatientTimelineResponse(
            patient=TimelinePatientHeader(
                id=patient.id,
                patient_code=patient.patient_code,
                full_name=patient.full_name,
                age=age_from_birth_date(patient.date_of_birth),
                latest_risk_level=patient.latest_risk_level,
            ),
            items=items,
            next_cursor=None,
        )

    async def update_handling(
        self,
        *,
        principal: Principal,
        patient_id: str,
        entry_id: str,
        request: HandlingUpdateRequest,
    ) -> HandlingUpdateResponse:
        self._require_staff(principal)
        response = await self.session.get(CheckinResponse, entry_id)
        question = None
        if not response:
            question = await self.session.get(HotlineQuestion, entry_id)
        if response and response.status != JobStatus.completed:
            raise APIError("conflict", "Entry đang được phân tích, chưa thể xử lý.", 409)
        if question and question.status != JobStatus.completed:
            raise APIError("conflict", "Entry đang được xử lý, chưa thể cập nhật.", 409)
        if not response and not question:
            raise APIError("not_found", "Không tìm thấy timeline entry.", 404)
        if response and response.patient_id != patient_id:
            raise APIError("not_found", "Timeline entry không thuộc bệnh nhân.", 404)
        if question and question.patient_id != patient_id:
            raise APIError("not_found", "Timeline entry không thuộc bệnh nhân.", 404)

        alert_id = response.staff_alert_id if response else question.staff_alert_id
        alert = await self.session.get(StaffAlert, alert_id) if alert_id else None
        if alert:
            alert.handling_status = request.handling_status
            alert.handled_by_user_id = principal.user_id
            alert.handled_at = now_utc()
            alert.handling_note = request.note
            alert.callback_at = request.callback_at
            alert.unread = False
        if response:
            response.handling_status = request.handling_status
        user = await self.session.get(User, principal.user_id)
        return HandlingUpdateResponse(
            entry_id=entry_id,
            handling_status=request.handling_status,
            handled_by=HandledByUser(id=user.id, full_name=user.full_name) if user else None,
            handled_at=alert.handled_at if alert else now_utc(),
            note=request.note,
        )

    async def _patient_summary(self, patient: Patient) -> PatientSummary:
        alert_result = await self.session.execute(
            select(StaffAlert)
            .where(StaffAlert.patient_id == patient.id, StaffAlert.deleted_at.is_(None))
            .order_by(StaffAlert.created_at.desc())
            .limit(1)
        )
        alert = alert_result.scalar_one_or_none()
        unread_result = await self.session.execute(
            select(func.count(StaffAlert.id)).where(
                StaffAlert.patient_id == patient.id,
                StaffAlert.unread.is_(True),
                StaffAlert.deleted_at.is_(None),
            )
        )
        return PatientSummary(
            patient_id=patient.id,
            patient_code=patient.patient_code,
            full_name=patient.full_name,
            age=age_from_birth_date(patient.date_of_birth),
            diagnoses=patient.diagnoses,
            latest_risk_level=patient.latest_risk_level,
            latest_summary=alert.summary if alert else None,
            latest_checkin_at=patient.latest_checkin_at,
            handling_status=alert.handling_status.value if alert else None,
            unread_alert_count=int(unread_result.scalar_one()),
        )

    async def _handling_for(self, alert_id: str | None) -> HandlingStatus | None:
        if not alert_id:
            return None
        alert = await self.session.get(StaffAlert, alert_id)
        return alert.handling_status if alert else None

    async def _count_patients_by_risk(self, risk: RiskLevel) -> int:
        result = await self.session.execute(
            select(func.count(Patient.id)).where(
                Patient.latest_risk_level == risk,
                Patient.is_active.is_(True),
                Patient.deleted_at.is_(None),
            )
        )
        return int(result.scalar_one())

    async def _count_jobs(self, job_type: JobType) -> int:
        result = await self.session.execute(
            select(func.count(Job.id)).where(
                Job.job_type == job_type,
                Job.status.notin_([JobStatus.completed, JobStatus.failed, JobStatus.cancelled]),
            )
        )
        return int(result.scalar_one())

    async def _count_table(self, model: type, *conditions) -> int:
        stmt = select(func.count(model.id))
        if conditions:
            stmt = stmt.where(*conditions)
        result = await self.session.execute(stmt)
        return int(result.scalar_one())

    def _require_staff(self, principal: Principal) -> None:
        if not principal.is_staff:
            raise APIError("forbidden", "Chỉ nhân viên y tế được truy cập chức năng này.", 403)
