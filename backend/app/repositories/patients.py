from sqlalchemy import Select, case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Patient
from app.models.enums import RiskLevel
from app.repositories.base import Repository


class PatientRepository(Repository[Patient]):
    def __init__(self, session: AsyncSession) -> None:
        super().__init__(session, Patient)

    async def by_code(self, patient_code: str) -> Patient | None:
        result = await self.session.execute(
            select(Patient).where(Patient.patient_code == patient_code, Patient.deleted_at.is_(None))
        )
        return result.scalar_one_or_none()

    async def active_count(self) -> int:
        result = await self.session.execute(
            select(func.count(Patient.id)).where(Patient.is_active.is_(True), Patient.deleted_at.is_(None))
        )
        return int(result.scalar_one())

    def priority_query(self, query: str | None, risk_level: RiskLevel | None) -> Select[tuple[Patient]]:
        stmt = select(Patient).where(Patient.is_active.is_(True), Patient.deleted_at.is_(None))
        if query:
            pattern = f"%{query.lower()}%"
            stmt = stmt.where(
                or_(
                    func.lower(Patient.full_name).like(pattern),
                    func.lower(Patient.patient_code).like(pattern),
                    Patient.phone_number.like(f"%{query}%"),
                    Patient.caregiver_phone_number.like(f"%{query}%"),
                )
            )
        if risk_level:
            stmt = stmt.where(Patient.latest_risk_level == risk_level)
        risk_rank = case(
            (Patient.latest_risk_level == RiskLevel.intervention, 1),
            (Patient.latest_risk_level == RiskLevel.attention, 2),
            (Patient.latest_risk_level == RiskLevel.normal, 3),
            else_=9,
        )
        return stmt.order_by(risk_rank.asc(), Patient.latest_checkin_at.desc().nullslast())
