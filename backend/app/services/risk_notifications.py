from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Patient, StaffNotification
from app.models.enums import RiskLevel, TimelineEntryType
from app.services.risk_classifier import merge_risk_levels
from app.services.risk_state import risk_priority
from app.utils.ids import new_id

_RISK_LABELS = {
    RiskLevel.normal: "Bình thường",
    RiskLevel.attention: "Cần chú ý",
    RiskLevel.intervention: "Cần can thiệp",
}


async def apply_patient_risk_update(
    session: AsyncSession,
    *,
    patient: Patient,
    new_level: RiskLevel,
    source_type: TimelineEntryType,
    source_id: str,
    summary: str,
) -> StaffNotification | None:
    previous = patient.latest_risk_level or RiskLevel.normal
    merged = merge_risk_levels(previous, new_level)
    patient.latest_risk_level = merged

    if merged == previous:
        return None

    title = f"{patient.full_name}: thay đổi mức nguy cơ"
    message = (
        f"Từ {_RISK_LABELS[previous]} → {_RISK_LABELS[merged]}. "
        f"{summary.strip()}"
    )[:500]

    notification = StaffNotification(
        id=new_id("snotif"),
        patient_id=patient.id,
        notification_type="risk_change",
        previous_risk_level=previous,
        new_risk_level=merged,
        source_type=source_type.value,
        source_id=source_id,
        title=title,
        message=message,
        unread=True,
    )
    session.add(notification)
    return notification


def is_risk_escalation(previous: RiskLevel, new: RiskLevel) -> bool:
    return risk_priority(new) > risk_priority(previous)