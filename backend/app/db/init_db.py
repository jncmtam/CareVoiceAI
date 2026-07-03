from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.security import hash_password
from app.db.base import Base
from app.db.session import engine
from app.models import (
    Appointment,
    Checkin,
    CheckinResponse,
    Medication,
    Patient,
    PatientUser,
    StaffAlert,
    User,
)
from app.models.enums import AudioStatus, Gender, HandlingStatus, JobStatus, RiskLevel, TimelineEntryType, UserRole
from app.utils.datetime import now_utc


async def create_tables() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def seed_demo_data(session: AsyncSession, settings: Settings) -> None:
    if not settings.seed_demo_data:
        return
    result = await session.execute(select(User).where(User.staff_code == "DD001"))
    if result.scalar_one_or_none():
        return

    staff = User(
        id="usr_demo_staff",
        email="nurse01@hospital.vn",
        staff_code="DD001",
        full_name="Nguyễn Thị Lan",
        role=UserRole.nurse,
        hashed_password=hash_password("secret"),
        department="Nội tiết",
        is_active=True,
    )
    patient_user = User(
        id="usr_demo_patient",
        phone_number="+84901234567",
        full_name="Trần Văn Bình",
        role=UserRole.patient,
        is_active=True,
    )
    patient = Patient(
        id="pat_001",
        patient_code="BN-2026-0001",
        full_name="Trần Văn Bình",
        date_of_birth=date(1958, 3, 20),
        gender=Gender.male,
        phone_number="+84901234567",
        caregiver_name="Trần Minh Anh",
        caregiver_phone_number="+84987654321",
        diagnoses=["type_2_diabetes", "hypertension"],
        address="Quận 3, TP.HCM",
        primary_doctor_name="BS. Lê Minh",
        notes="Nghe kém, ưu tiên gọi cho người nhà sau 19:00.",
        latest_risk_level=RiskLevel.attention,
        latest_checkin_at=now_utc() - timedelta(hours=2),
        next_appointment_at=now_utc() + timedelta(days=7),
        is_active=True,
        created_by_user_id=staff.id,
    )
    second = Patient(
        id="pat_002",
        patient_code="BN-2026-0002",
        full_name="Nguyễn Thị Hoa",
        date_of_birth=date(1966, 9, 12),
        gender=Gender.female,
        phone_number="+84903334455",
        caregiver_name="Phạm Quang Minh",
        caregiver_phone_number="+84906667788",
        diagnoses=["heart_failure", "dyslipidemia"],
        latest_risk_level=RiskLevel.normal,
        is_active=True,
        created_by_user_id=staff.id,
    )
    link = PatientUser(id="pu_demo_001", user_id=patient_user.id, patient_id=patient.id)
    med = Medication(
        id="med_001",
        patient_id=patient.id,
        name="Metformin",
        strength="500mg",
        dosage="1 viên",
        frequency="2 lần/ngày",
        times_of_day=["morning", "evening"],
        instructions="Uống sau ăn sáng và tối.",
        is_active=True,
    )
    appointment = Appointment(
        id="appt_001",
        patient_id=patient.id,
        appointment_at=now_utc() + timedelta(days=7),
        department="Nội tiết",
        doctor_name="BS. Lê Minh",
        status="scheduled",
    )
    checkin = Checkin(
        id="chk_demo_today",
        patient_id=patient.id,
        scheduled_for=date.today(),
        status="ready",
        question_text="Hôm nay bác có thấy mệt, khó thở hoặc đau ngực không?",
        audio_status=AudioStatus.unavailable,
        expires_at=now_utc() + timedelta(hours=12),
    )
    response = CheckinResponse(
        id="resp_demo_001",
        checkin_id=checkin.id,
        patient_id=patient.id,
        quick_answer_id="yes",
        client_request_id="seed_demo",
        status=JobStatus.completed,
        transcript="Hôm nay tôi hơi chóng mặt sau khi uống thuốc.",
        summary="Bệnh nhân báo chóng mặt sau uống thuốc.",
        risk_level=RiskLevel.attention,
        risk_reasons=["Có triệu chứng chóng mặt sau dùng thuốc"],
        needs_staff_review=True,
        handling_status=HandlingStatus.new,
    )
    alert = StaffAlert(
        id="alert_001",
        patient_id=patient.id,
        source_type=TimelineEntryType.checkin_response,
        source_id=response.id,
        risk_level=RiskLevel.attention,
        summary=response.summary,
        handling_status=HandlingStatus.new,
        unread=True,
    )
    response.staff_alert_id = alert.id

    session.add_all(
        [staff, patient_user, patient, second, link, med, appointment, checkin, response, alert]
    )
    await session.commit()

