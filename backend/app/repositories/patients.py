from sqlalchemy import Select, case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Patient
from app.models.enums import RiskLevel
from app.repositories.base import Repository
from app.utils.patient_validation import normalize_patient_code, patient_code_lookup_candidates


class PatientRepository(Repository[Patient]):
    def __init__(self, session: AsyncSession) -> None:
        super().__init__(session, Patient)

    async def by_code(self, patient_code: str) -> Patient | None:
        result = await self.session.execute(
            select(Patient).where(Patient.patient_code == patient_code, Patient.deleted_at.is_(None))
        )
        return result.scalar_one_or_none()

    async def by_code_lookup(self, raw_code: str) -> Patient | None:
        codes = patient_code_lookup_candidates(raw_code)
        if not codes:
            return None
        result = await self.session.execute(
            select(Patient).where(Patient.patient_code.in_(codes), Patient.deleted_at.is_(None))
        )
        patients = list(result.scalars().all())
        if not patients:
            return None
        preferred = normalize_patient_code(raw_code)
        for patient in patients:
            if patient.patient_code == preferred:
                return patient
        for code in codes:
            for patient in patients:
                if patient.patient_code == code:
                    return patient
        return patients[0]

    async def by_phone(self, phone_number: str) -> Patient | None:
        result = await self.session.execute(
            select(Patient).where(
                Patient.phone_number == phone_number,
                Patient.deleted_at.is_(None),
                Patient.is_active.is_(True),
            )
        )
        return result.scalar_one_or_none()

    async def next_patient_sequence(self, year: int) -> int:
        prefix = f"VC-{year}-"
        result = await self.session.execute(
            select(func.max(Patient.patient_code)).where(Patient.patient_code.like(f"{prefix}%"))
        )
        max_code = result.scalar_one_or_none()
        if not max_code:
            return 1
        suffix = max_code.rsplit("-", 1)[-1]
        try:
            return int(suffix) + 1
        except ValueError:
            result = await self.session.execute(
                select(func.count(Patient.id)).where(Patient.patient_code.like(f"{prefix}%"))
            )
            return int(result.scalar_one()) + 1

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
