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
    Job,
    Medication,
    Patient,
    PatientUser,
    StaffAlert,
    User,
)
from app.models.enums import (
    AudioStatus,
    Gender,
    HandlingStatus,
    JobStatus,
    JobType,
    RiskLevel,
    TimelineEntryType,
    UserRole,
)
from app.db.extra_demo_patients import build_extra_demo_patients
from app.db.production_accounts import (
    NURSE_LOGIN,
    NURSE_PASSWORD,
    PATIENT_LOGIN,
    PATIENT_PASSWORD,
    PRIMARY_PATIENT_CODE,
    PRIMARY_PATIENT_PHONE,
)
from app.utils.datetime import now_utc
from app.utils.patient_validation import legacy_patient_code_to_vc


async def create_tables() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def migrate_legacy_patient_codes(session: AsyncSession) -> int:
    result = await session.execute(select(Patient).where(Patient.patient_code.like("BN-%")))
    updated = 0
    for patient in result.scalars():
        new_code = legacy_patient_code_to_vc(patient.patient_code)
        if not new_code or new_code == patient.patient_code:
            continue
        conflict = await session.execute(
            select(Patient.id).where(Patient.patient_code == new_code, Patient.id != patient.id)
        )
        if conflict.scalar_one_or_none():
            continue
        patient.patient_code = new_code
        updated += 1
    if updated:
        await session.commit()
    return updated


async def seed_demo_data(session: AsyncSession, settings: Settings) -> None:
    if not settings.seed_demo_data:
        return
    result = await session.execute(select(User).where(User.id == "usr_demo_staff"))
    if result.scalar_one_or_none():
        return

    staff = User(
        id="usr_demo_staff",
        email=NURSE_LOGIN,
        staff_code=NURSE_LOGIN,
        full_name="Ngô Ngọc Triệu Mẫn",
        role=UserRole.nurse,
        hashed_password=hash_password(NURSE_PASSWORD),
        department="Nội tiết",
        is_active=True,
    )
    patient_user = User(
        id="usr_demo_patient",
        email=PATIENT_LOGIN,
        phone_number=PRIMARY_PATIENT_PHONE,
        full_name="Chu Minh Tâm",
        role=UserRole.patient,
        hashed_password=hash_password(PATIENT_PASSWORD),
        is_active=True,
    )
    patient = Patient(
        id="pat_001",
        patient_code=PRIMARY_PATIENT_CODE,
        full_name="Chu Minh Tâm",
        date_of_birth=date(1998, 7, 15),
        gender=Gender.male,
        phone_number=PRIMARY_PATIENT_PHONE,
        caregiver_name="Người nhà",
        caregiver_phone_number=None,
        diagnoses=["type_2_diabetes", "hypertension"],
        address="TP.HCM",
        primary_doctor_name="BS. Lê Minh",
        notes="Bệnh nhân chính — SĐT 0327628468.",
        latest_risk_level=RiskLevel.intervention,
        latest_checkin_at=now_utc() - timedelta(hours=2),
        next_appointment_at=now_utc() + timedelta(days=7),
        is_active=True,
        created_by_user_id=staff.id,
    )
    second = Patient(
        id="pat_002",
        patient_code="VC-2026-000002",
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
    third = Patient(
        id="pat_003",
        patient_code="VC-2026-000003",
        full_name="Lê Quốc Đạt",
        date_of_birth=date(1971, 1, 5),
        gender=Gender.male,
        phone_number="+84908889900",
        diagnoses=["post_knee_surgery"],
        latest_risk_level=RiskLevel.normal,
        latest_checkin_at=now_utc(),
        next_appointment_at=now_utc() + timedelta(days=14),
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
    seed_job = Job(
        id="checkin_job_seed_demo",
        job_type=JobType.checkin_analysis,
        status=JobStatus.completed,
        progress=100,
        stage="completed",
        patient_id=patient.id,
        source_id="resp_demo_001",
        completed_at=now_utc(),
    )
    response = CheckinResponse(
        id="resp_demo_001",
        checkin_id=checkin.id,
        patient_id=patient.id,
        quick_answer_id="yes",
        client_request_id="seed_demo",
        status=JobStatus.completed,
        job_id=seed_job.id,
        transcript="Hôm nay tôi hơi chóng mặt sau khi uống thuốc.",
        summary="Bệnh nhân báo chóng mặt sau uống thuốc.",
        risk_level=RiskLevel.intervention,
        risk_reasons=["Check-in: bệnh nhân báo khó thở", "Check-in: bệnh nhân báo đau ngực"],
        needs_staff_review=True,
        handling_status=HandlingStatus.new,
    )
    alert = StaffAlert(
        id="alert_001",
        patient_id=patient.id,
        source_type=TimelineEntryType.checkin_response,
        source_id=response.id,
        risk_level=RiskLevel.intervention,
        summary=response.summary,
        handling_status=HandlingStatus.new,
        unread=True,
    )
    response.staff_alert_id = alert.id

    session.add_all([staff, patient_user])

    await session.flush()

    extra_patients, extra_alerts = build_extra_demo_patients(staff.id)
    session.add_all([patient, second, third, *extra_patients])

    await session.flush()

    session.add(link)

    await session.flush()

    session.add_all([med, appointment, checkin])

    await session.flush()

    session.add(seed_job)

    await session.flush()

    session.add(response)

    await session.flush()

    session.add(alert)
    session.add_all(extra_alerts)

    await session.commit()
