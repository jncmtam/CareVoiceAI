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
    PatientDeleteResponse,
    PatientResponse,
    PatientUpdateRequest,
)
from app.services.auth import Principal
from app.services.mappers import appointment_out, medication_out, patient_profile
from app.utils.datetime import now_utc
from app.utils.ids import new_id
from app.utils.patient_validation import (
    generate_patient_code,
    validate_optional_phone_number,
    validate_phone_number,
)


class PatientService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = PatientRepository(session)

    async def create_patient(
        self, request: PatientCreateRequest, principal: Principal
    ) -> PatientResponse:
        if principal.role not in {UserRole.nurse, UserRole.doctor, UserRole.admin}:
            raise APIError("forbidden", "Chỉ nhân viên y tế được tạo hồ sơ bệnh nhân.", 403)

        patient_code = await self._allocate_patient_code()
        phone_number = validate_phone_number(request.phone_number)
        caregiver_phone = validate_optional_phone_number(
            request.caregiver_phone_number, field_name="caregiver_phone_number"
        )
        full_name = request.full_name.strip()
        if len(full_name) < 2:
            raise APIError("validation_error", "Họ tên phải có ít nhất 2 ký tự.", 422)

        existing_phone = await self.repo.by_phone(phone_number)
        if existing_phone:
            raise APIError(
                "conflict",
                "Số điện thoại đã được dùng cho bệnh nhân khác.",
                409,
                details={"patient_code": existing_phone.patient_code},
            )

        patient = Patient(
            id=new_id("pat"),
            patient_code=patient_code,
            full_name=full_name,
            date_of_birth=request.date_of_birth,
            gender=request.gender,
            phone_number=phone_number,
            caregiver_name=request.caregiver_name.strip() if request.caregiver_name else None,
            caregiver_phone_number=caregiver_phone,
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

    async def _allocate_patient_code(self) -> str:
        year = now_utc().year
        for _ in range(10):
            sequence = await self.repo.next_patient_sequence(year)
            code = generate_patient_code(sequence, year)
            if not await self.repo.by_code(code):
                return code
        raise APIError("conflict", "Không thể tạo mã bệnh nhân mới, vui lòng thử lại.", 409)

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

        updates = request.model_dump(exclude_unset=True)
        if "full_name" in updates and updates["full_name"] is not None:
            full_name = updates["full_name"].strip()
            if len(full_name) < 2:
                raise APIError("validation_error", "Họ tên phải có ít nhất 2 ký tự.", 422)
            updates["full_name"] = full_name
        if "phone_number" in updates and updates["phone_number"] is not None:
            phone_number = validate_phone_number(updates["phone_number"])
            existing_phone = await self.repo.by_phone(phone_number)
            if existing_phone and existing_phone.id != patient.id:
                raise APIError("conflict", "Số điện thoại đã được dùng cho bệnh nhân khác.", 409)
            updates["phone_number"] = phone_number
        if "caregiver_phone_number" in updates:
            updates["caregiver_phone_number"] = validate_optional_phone_number(
                updates.get("caregiver_phone_number"), field_name="caregiver_phone_number"
            )
        if "caregiver_name" in updates and updates["caregiver_name"] is not None:
            updates["caregiver_name"] = updates["caregiver_name"].strip() or None

        for field, value in updates.items():
            setattr(patient, field, value)
        patient.version += 1
        return PatientResponse(patient=patient_profile(patient))

    async def deactivate_patient(self, patient_id: str, principal: Principal) -> PatientDeleteResponse:
        if not principal.is_staff:
            raise APIError("forbidden", "Chỉ nhân viên y tế được xoá hồ sơ bệnh nhân.", 403)
        patient = await self.repo.get(patient_id)
        if not patient or patient.deleted_at:
            raise APIError("not_found", "Không tìm thấy bệnh nhân.", 404)
        patient.is_active = False
        patient.deleted_at = now_utc()
        return PatientDeleteResponse(patient_id=patient.id)

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