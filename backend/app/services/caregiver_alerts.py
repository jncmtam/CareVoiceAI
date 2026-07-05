from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CaregiverAlertLog, Patient
from app.models.enums import RiskLevel
from app.utils.ids import new_id


class CaregiverAlertService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def maybe_notify(
        self,
        *,
        patient_id: str,
        trigger_type: str,
        source_id: str | None,
        summary: str,
        risk_level: RiskLevel,
    ) -> CaregiverAlertLog | None:
        if risk_level not in {RiskLevel.attention, RiskLevel.intervention}:
            return None
        patient = await self.session.get(Patient, patient_id)
        if not patient or not patient.caregiver_phone_number:
            return None

        message = (
            f"[CareVoice AI] BN {patient.full_name} ({patient.patient_code}) cần chú ý: {summary} "
            f"Vui lòng liên hệ bệnh nhân hoặc điều dưỡng."
        )
        log = CaregiverAlertLog(
            id=new_id("cg_alert"),
            patient_id=patient_id,
            trigger_type=trigger_type,
            source_id=source_id,
            caregiver_phone=patient.caregiver_phone_number,
            message=message,
            channel="sms_mock",
            status="sent",
        )
        self.session.add(log)
        return log