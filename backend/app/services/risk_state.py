from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CheckinResponse, Patient, StaffAlert
from app.models.enums import HandlingStatus, JobStatus, RiskLevel

OPEN_HANDLING_STATUSES = {
    HandlingStatus.new,
    HandlingStatus.viewed,
    HandlingStatus.called_back,
}


def risk_priority(level: RiskLevel | None) -> int:
    return {
        RiskLevel.intervention: 3,
        RiskLevel.attention: 2,
        RiskLevel.normal: 1,
    }.get(level, 0)


def stabilized_risk_level(level: RiskLevel | None) -> RiskLevel:
    if level == RiskLevel.intervention:
        return RiskLevel.attention
    return RiskLevel.normal


async def sync_patient_risk_level(session: AsyncSession, patient_id: str) -> None:
    patient = await session.get(Patient, patient_id)
    if not patient:
        return

    open_alerts_result = await session.execute(
        select(StaffAlert)
        .where(
            StaffAlert.patient_id == patient_id,
            StaffAlert.deleted_at.is_(None),
            StaffAlert.handling_status.in_(OPEN_HANDLING_STATUSES),
        )
        .order_by(StaffAlert.created_at.desc())
    )
    open_alerts = list(open_alerts_result.scalars())
    if open_alerts:
        patient.latest_risk_level = max(
            (alert.risk_level for alert in open_alerts),
            key=risk_priority,
            default=RiskLevel.normal,
        )
        return

    checkin_result = await session.execute(
        select(CheckinResponse)
        .where(
            CheckinResponse.patient_id == patient_id,
            CheckinResponse.deleted_at.is_(None),
            CheckinResponse.status == JobStatus.completed,
        )
        .order_by(CheckinResponse.created_at.desc())
        .limit(1)
    )
    latest_checkin = checkin_result.scalar_one_or_none()
    if not latest_checkin or not latest_checkin.risk_level:
        patient.latest_risk_level = RiskLevel.normal
        return

    if latest_checkin.handling_status == HandlingStatus.resolved:
        patient.latest_risk_level = stabilized_risk_level(latest_checkin.risk_level)
    else:
        patient.latest_risk_level = latest_checkin.risk_level


async def count_actionable_patients(session: AsyncSession, risk_level: RiskLevel) -> int:
    result = await session.execute(
        select(Patient.id)
        .join(StaffAlert, StaffAlert.patient_id == Patient.id)
        .where(
            Patient.is_active.is_(True),
            Patient.deleted_at.is_(None),
            StaffAlert.deleted_at.is_(None),
            StaffAlert.handling_status.in_(OPEN_HANDLING_STATUSES),
            StaffAlert.risk_level == risk_level,
        )
        .distinct()
    )
    return len(result.scalars().all())