"""Tài khoản production/demo thống nhất — đồng bộ mỗi lần khởi động API."""

from datetime import date

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password
from app.models import Patient, PatientUser, StaffAlert, User
from app.models.enums import Gender, UserRole

NURSE_LOGIN = "nurse"
NURSE_PASSWORD = "nurse"
PATIENT_LOGIN = "patient"
PATIENT_PASSWORD = "patient"
PRIMARY_PATIENT_PHONE = "+84327628468"
PRIMARY_PATIENT_CODE = "VC-2026-000001"
PRIMARY_CAREGIVER_NAME = "Trần Minh Anh"
PRIMARY_CAREGIVER_PHONE = "+84987654321"


async def sync_production_accounts(session: AsyncSession) -> None:
    nurse = await _upsert_nurse(session)
    await _upsert_primary_patient(session, nurse_id=nurse.id)
    await _retire_legacy_demo_patient(session)
    await session.commit()


async def _upsert_nurse(session: AsyncSession) -> User:
    result = await session.execute(
        select(User).where(
            User.deleted_at.is_(None),
            (User.staff_code == NURSE_LOGIN) | (User.staff_code == "DD001") | (User.id == "usr_demo_staff"),
        )
    )
    nurse = result.scalar_one_or_none()
    if nurse is None:
        nurse = User(
            id="usr_demo_staff",
            email=NURSE_LOGIN,
            staff_code=NURSE_LOGIN,
            full_name="Ngô Ngọc Triệu Mẫn",
            role=UserRole.nurse,
            hashed_password=hash_password(NURSE_PASSWORD),
            department="Nội tiết",
            is_active=True,
        )
        session.add(nurse)
    else:
        nurse.email = NURSE_LOGIN
        nurse.staff_code = NURSE_LOGIN
        nurse.full_name = "Ngô Ngọc Triệu Mẫn"
        nurse.hashed_password = hash_password(NURSE_PASSWORD)
        nurse.role = UserRole.nurse
        nurse.is_active = True
    await session.flush()
    return nurse


async def _upsert_primary_patient(session: AsyncSession, *, nurse_id: str) -> Patient:
    result = await session.execute(select(Patient).where(Patient.id == "pat_001"))
    patient = result.scalar_one_or_none()
    if patient is None:
        patient = Patient(
            id="pat_001",
            patient_code=PRIMARY_PATIENT_CODE,
            full_name="Chu Minh Tâm",
            date_of_birth=date(1998, 7, 15),
            gender=Gender.male,
            phone_number=PRIMARY_PATIENT_PHONE,
            caregiver_name=PRIMARY_CAREGIVER_NAME,
            caregiver_phone_number=PRIMARY_CAREGIVER_PHONE,
            diagnoses=["type_2_diabetes", "hypertension"],
            address="TP.HCM",
            primary_doctor_name="BS. Lê Minh",
            notes="Bệnh nhân chính — SĐT 0327628468.",
            is_active=True,
            created_by_user_id=nurse_id,
        )
        session.add(patient)
    else:
        patient.patient_code = PRIMARY_PATIENT_CODE
        patient.full_name = "Chu Minh Tâm"
        patient.phone_number = PRIMARY_PATIENT_PHONE
        patient.caregiver_name = PRIMARY_CAREGIVER_NAME
        patient.caregiver_phone_number = PRIMARY_CAREGIVER_PHONE
        patient.date_of_birth = date(1998, 7, 15)
        patient.gender = Gender.male
        patient.is_active = True
        patient.notes = "Bệnh nhân chính — SĐT 0327628468."
    await session.flush()

    user_result = await session.execute(
        select(User).join(PatientUser).where(PatientUser.patient_id == patient.id).limit(1)
    )
    user = user_result.scalar_one_or_none()
    if user is None:
        user = User(
            id="usr_demo_patient",
            email=PATIENT_LOGIN,
            full_name=patient.full_name,
            role=UserRole.patient,
            phone_number=PRIMARY_PATIENT_PHONE,
            hashed_password=hash_password(PATIENT_PASSWORD),
            is_active=True,
        )
        link = PatientUser(id="pu_demo_001", user_id=user.id, patient_id=patient.id)
        session.add_all([user, link])
    else:
        user.email = PATIENT_LOGIN
        user.full_name = patient.full_name
        user.phone_number = PRIMARY_PATIENT_PHONE
        user.hashed_password = hash_password(PATIENT_PASSWORD)
        user.role = UserRole.patient
        user.is_active = True
    await session.flush()
    return patient


async def _retire_legacy_demo_patient(session: AsyncSession) -> None:
    result = await session.execute(select(Patient).where(Patient.id == "pat_010"))
    legacy = result.scalar_one_or_none()
    if legacy:
        legacy.is_active = False
    alert_result = await session.execute(select(StaffAlert).where(StaffAlert.patient_id == "pat_010"))
    for alert in alert_result.scalars():
        alert.unread = False