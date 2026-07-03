from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import APIError
from app.models import Appointment as AppointmentModel
from app.models import Medication as MedicationModel
from app.models import Patient
from app.models.enums import RiskLevel, UserRole
from app.repositories.patients import PatientRepository
from app.schemas.patients import (
    AppointmentListResponse,
    MedicationListResponse,
    PatientCreateRequest,
    PatientResponse,
    PatientUpdateRequest,
)
from app.services.auth import Principal
from app.services.mappers import appointment_out, medication_out, patient_profile
from app.utils.ids import new_id


class PatientService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = PatientRepository(session)

    async def create_patient(
        self, request: PatientCreateRequest, principal: Principal
    ) -> PatientResponse:
        if principal.role not in {UserRole.nurse, UserRole.doctor, UserRole.admin}:
            raise APIError("forbidden", "Chỉ nhân viên y tế được tạo hồ sơ bệnh nhân.", 403)
        existing = await self.repo.by_code(request.patient_code)
        if existing:
            raise APIError("conflict", "Mã bệnh nhân đã tồn tại.", 409)
        patient = Patient(
            id=new_id("pat"),
            patient_code=request.patient_code,
            full_name=request.full_name,
            date_of_birth=request.date_of_birth,
            gender=request.gender,
            phone_number=request.phone_number,
            caregiver_name=request.caregiver_name,
            caregiver_phone_number=request.caregiver_phone_number,
            diagnoses=request.diagnoses,
            address=request.address,
            primary_doctor_name=request.primary_doctor_name,
            notes=request.notes,
            latest_risk_level=RiskLevel.normal,
            is_active=True,
            created_by_user_id=principal.user_id,
        )
        await self.repo.add(patient)
        return PatientResponse(patient=patient_profile(patient))

    async def get_patient(
        self, patient_id: str, *, include_notes: bool = True
    ) -> PatientResponse:
        patient = await self.repo.get(patient_id)
        if not patient or patient.deleted_at:
            raise APIError("not_found", "Không tìm thấy bệnh nhân.", 404)
        return PatientResponse(patient=patient_profile(patient, include_notes=include_notes))

    async def update_patient(
        self, patient_id: str, request: PatientUpdateRequest, principal: Principal
    ) -> PatientResponse:
        if not principal.is_staff:
            raise APIError("forbidden", "Chỉ nhân viên y tế được cập nhật hồ sơ.", 403)
        patient = await self.repo.get(patient_id)
        if not patient or patient.deleted_at:
            raise APIError("not_found", "Không tìm thấy bệnh nhân.", 404)
        for field, value in request.model_dump(exclude_unset=True).items():
            setattr(patient, field, value)
        patient.version += 1
        return PatientResponse(patient=patient_profile(patient))

    async def medications(self, patient_id: str) -> MedicationListResponse:
        result = await self.session.execute(
            select(MedicationModel)
            .where(
                MedicationModel.patient_id == patient_id,
                MedicationModel.deleted_at.is_(None),
                MedicationModel.is_active.is_(True),
            )
            .order_by(MedicationModel.created_at.desc())
        )
        return MedicationListResponse(medications=[medication_out(item) for item in result.scalars()])

    async def appointments(self, patient_id: str) -> AppointmentListResponse:
        result = await self.session.execute(
            select(AppointmentModel)
            .where(AppointmentModel.patient_id == patient_id, AppointmentModel.deleted_at.is_(None))
            .order_by(AppointmentModel.appointment_at.asc())
        )
        return AppointmentListResponse(appointments=[appointment_out(item) for item in result.scalars()])

    async def count_by_risk(self, risk_level: RiskLevel) -> int:
        result = await self.session.execute(
            select(func.count(Patient.id)).where(
                Patient.deleted_at.is_(None),
                Patient.is_active.is_(True),
                Patient.latest_risk_level == risk_level,
            )
        )
        return int(result.scalar_one())

