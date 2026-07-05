from datetime import date

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import APIError
from app.integrations.vnpt import VNPTGateway
from app.models import DailyHealthTip, Medication, Patient
from app.schemas.daily_tip import DailyTipResponse
from app.services.auth import Principal
from app.utils.diagnosis_labels import diagnosis_labels
from app.utils.ids import new_id


class DailyTipService:
    def __init__(self, session: AsyncSession, settings: Settings, gateway: VNPTGateway) -> None:
        self.session = session
        self.settings = settings
        self.gateway = gateway

    async def today(self, principal: Principal) -> DailyTipResponse:
        if not principal.patient_id:
            raise APIError("forbidden", "Tài khoản không gắn với bệnh nhân.", 403)
        patient = await self.session.get(Patient, principal.patient_id)
        if not patient:
            raise APIError("not_found", "Không tìm thấy bệnh nhân.", 404)

        today = date.today()
        labels = diagnosis_labels(patient.diagnoses)
        cached = await self._cached_tip(patient.id, today)
        if cached:
            return DailyTipResponse(
                tip_date=today,
                tip_text=cached.tip_text,
                source_scope=cached.source_scope,
                diagnoses_context=labels,
            )

        medications = await self._active_medications(patient.id)
        tip_text, source_scope = await self.gateway.daily_health_tip(
            diagnoses=labels,
            medications=medications,
            patient_id=patient.id,
            tip_date=today.isoformat(),
        )
        row = DailyHealthTip(
            id=new_id("tip"),
            patient_id=patient.id,
            tip_date=today,
            tip_text=tip_text,
            source_scope=source_scope,
        )
        self.session.add(row)
        await self.session.flush()
        return DailyTipResponse(
            tip_date=today,
            tip_text=tip_text,
            source_scope=source_scope,
            diagnoses_context=labels,
        )

    async def _cached_tip(self, patient_id: str, tip_date: date) -> DailyHealthTip | None:
        result = await self.session.execute(
            select(DailyHealthTip).where(
                DailyHealthTip.patient_id == patient_id,
                DailyHealthTip.tip_date == tip_date,
            )
        )
        return result.scalar_one_or_none()

    async def _active_medications(self, patient_id: str) -> list[str]:
        result = await self.session.execute(
            select(Medication.name, Medication.instructions)
            .where(
                Medication.patient_id == patient_id,
                Medication.deleted_at.is_(None),
                Medication.is_active.is_(True),
            )
            .order_by(func.lower(Medication.name))
        )
        items: list[str] = []
        for name, instructions in result.all():
            line = name
            if instructions:
                line = f"{name} ({instructions})"
            items.append(line)
        return items