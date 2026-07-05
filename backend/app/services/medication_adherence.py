from datetime import date

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import APIError
from app.models import Medication, MedicationAdherenceLog, Patient
from app.schemas.adherence import (
    MedicationAdherenceRequest,
    MedicationAdherenceResponse,
    MedicationAdherenceSummary,
)
from app.services.auth import Principal
from app.utils.ids import new_id


class MedicationAdherenceService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def record(
        self, request: MedicationAdherenceRequest, principal: Principal
    ) -> MedicationAdherenceResponse:
        patient_id = principal.patient_id
        if not patient_id:
            raise APIError("forbidden", "Chỉ bệnh nhân/người nhà ghi nhận uống thuốc.", 403)

        medication = await self.session.get(Medication, request.medication_id)
        if not medication or medication.patient_id != patient_id or medication.deleted_at:
            raise APIError("not_found", "Không tìm thấy thuốc.", 404)

        today = date.today()
        existing = await self.session.execute(
            select(MedicationAdherenceLog).where(
                MedicationAdherenceLog.patient_id == patient_id,
                MedicationAdherenceLog.medication_id == request.medication_id,
                MedicationAdherenceLog.scheduled_date == today,
                MedicationAdherenceLog.slot == request.slot,
            )
        )
        log = existing.scalar_one_or_none()
        if log:
            log.taken = request.taken
            log.recorded_via = request.recorded_via
        else:
            log = MedicationAdherenceLog(
                id=new_id("med_log"),
                patient_id=patient_id,
                medication_id=request.medication_id,
                slot=request.slot,
                scheduled_date=today,
                taken=request.taken,
                recorded_via=request.recorded_via,
            )
            self.session.add(log)

        missed_today = await self._missed_count_for_patient(patient_id, today)
        return MedicationAdherenceResponse(
            medication_id=request.medication_id,
            slot=request.slot,
            taken=request.taken,
            missed_doses_today=missed_today,
            message="Đã ghi nhận uống thuốc." if request.taken else "Đã ghi nhận chưa uống thuốc.",
        )

    async def summary_for_patient(self, patient_id: str, *, day: date | None = None) -> MedicationAdherenceSummary:
        target_day = day or date.today()
        missed = await self._missed_count_for_patient(patient_id, target_day)
        return MedicationAdherenceSummary(patient_id=patient_id, missed_doses_today=missed)

    async def _missed_count_for_patient(self, patient_id: str, day: date) -> int:
        patient = await self.session.get(Patient, patient_id)
        if not patient:
            return 0
        meds_result = await self.session.execute(
            select(Medication).where(
                Medication.patient_id == patient_id,
                Medication.deleted_at.is_(None),
                Medication.is_active.is_(True),
            )
        )
        medications = list(meds_result.scalars())
        if not medications:
            return 0

        expected_slots = 0
        for med in medications:
            slots = med.times_of_day or ["morning"]
            if isinstance(slots, list):
                expected_slots += len(slots)
            else:
                expected_slots += 1

        taken_result = await self.session.execute(
            select(func.count(MedicationAdherenceLog.id)).where(
                MedicationAdherenceLog.patient_id == patient_id,
                MedicationAdherenceLog.scheduled_date == day,
                MedicationAdherenceLog.taken.is_(True),
            )
        )
        taken_count = int(taken_result.scalar_one())
        missed_logs = await self.session.execute(
            select(func.count(MedicationAdherenceLog.id)).where(
                MedicationAdherenceLog.patient_id == patient_id,
                MedicationAdherenceLog.scheduled_date == day,
                MedicationAdherenceLog.taken.is_(False),
            )
        )
        explicit_missed = int(missed_logs.scalar_one())
        return max(explicit_missed, expected_slots - taken_count)