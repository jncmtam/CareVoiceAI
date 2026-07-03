from __future__ import annotations

from datetime import date, datetime
from typing import Any

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy import (
    Enum as SAEnum,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, SoftDeleteMixin, TimestampMixin, VersionMixin
from app.models.enums import (
    AudioStatus,
    DocumentType,
    Gender,
    HandlingStatus,
    JobStatus,
    JobType,
    OcrMode,
    PushEnvironment,
    RiskLevel,
    TimelineEntryType,
    UserRole,
)


def enum_column(enum: type, **kwargs: Any) -> Any:
    return mapped_column(SAEnum(enum, native_enum=False, validate_strings=True), **kwargs)


class User(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, index=True)
    staff_code: Mapped[str | None] = mapped_column(String(64), unique=True, index=True)
    phone_number: Mapped[str | None] = mapped_column(String(32), index=True)
    full_name: Mapped[str] = mapped_column(String(255))
    role: Mapped[UserRole] = enum_column(UserRole, nullable=False, index=True)
    hashed_password: Mapped[str | None] = mapped_column(String(255))
    department: Mapped[str | None] = mapped_column(String(255))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    patient_links: Mapped[list[PatientUser]] = relationship(back_populates="user")
    refresh_tokens: Mapped[list[RefreshToken]] = relationship(back_populates="user")


class Patient(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "patients"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    patient_code: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(255), index=True)
    date_of_birth: Mapped[date | None] = mapped_column(Date)
    gender: Mapped[Gender | None] = enum_column(Gender, nullable=True)
    phone_number: Mapped[str | None] = mapped_column(String(32), index=True)
    caregiver_name: Mapped[str | None] = mapped_column(String(255))
    caregiver_phone_number: Mapped[str | None] = mapped_column(String(32), index=True)
    diagnoses: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    address: Mapped[str | None] = mapped_column(Text)
    primary_doctor_name: Mapped[str | None] = mapped_column(String(255))
    notes: Mapped[str | None] = mapped_column(Text)
    latest_risk_level: Mapped[RiskLevel | None] = enum_column(RiskLevel, nullable=True, index=True)
    latest_checkin_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    next_appointment_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    created_by_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"))

    user_links: Mapped[list[PatientUser]] = relationship(back_populates="patient")
    medications: Mapped[list[Medication]] = relationship(back_populates="patient")
    appointments: Mapped[list[Appointment]] = relationship(back_populates="patient")


class PatientUser(Base, TimestampMixin):
    __tablename__ = "patient_users"
    __table_args__ = (UniqueConstraint("user_id", "patient_id", name="uq_patient_users_user_patient"),)

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    relationship_type: Mapped[str] = mapped_column(String(32), default="patient")

    user: Mapped[User] = relationship(back_populates="patient_links")
    patient: Mapped[Patient] = relationship(back_populates="user_links")


class RefreshToken(Base, TimestampMixin):
    __tablename__ = "refresh_tokens"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    device_id: Mapped[str | None] = mapped_column(String(255), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    rotated_from_id: Mapped[str | None] = mapped_column(String(40))

    user: Mapped[User] = relationship(back_populates="refresh_tokens")


class OtpSession(Base, TimestampMixin):
    __tablename__ = "otp_sessions"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    phone_number: Mapped[str] = mapped_column(String(32), index=True)
    patient_code: Mapped[str | None] = mapped_column(String(64), index=True)
    code_hash: Mapped[str] = mapped_column(String(255))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    can_resend_after: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    attempt_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)


class IdempotencyKey(Base, TimestampMixin):
    __tablename__ = "idempotency_keys"
    __table_args__ = (
        UniqueConstraint("scope", "actor_id", "client_request_id", name="uq_idempotency_scope_actor_key"),
    )

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    scope: Mapped[str] = mapped_column(String(80), index=True)
    actor_id: Mapped[str] = mapped_column(String(40), index=True)
    client_request_id: Mapped[str] = mapped_column(String(128), index=True)
    request_hash: Mapped[str] = mapped_column(String(64))
    response_status: Mapped[int] = mapped_column(Integer)
    response_body: Mapped[dict[str, Any]] = mapped_column(JSON)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)


class Job(Base, TimestampMixin):
    __tablename__ = "jobs"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    job_type: Mapped[JobType] = enum_column(JobType, nullable=False, index=True)
    status: Mapped[JobStatus] = enum_column(JobStatus, nullable=False, index=True)
    progress: Mapped[int | None] = mapped_column(Integer)
    stage: Mapped[str | None] = mapped_column(String(128))
    poll_after_seconds: Mapped[float | None]
    patient_id: Mapped[str | None] = mapped_column(ForeignKey("patients.id"), index=True)
    source_id: Mapped[str | None] = mapped_column(String(40), index=True)
    vendor_job_id: Mapped[str | None] = mapped_column(String(255), index=True)
    result: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    error_code: Mapped[str | None] = mapped_column(String(64))
    error_message: Mapped[str | None] = mapped_column(Text)
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class MedicalDocument(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "medical_documents"
    __table_args__ = (
        UniqueConstraint("patient_id", "client_request_id", name="uq_documents_patient_request"),
    )

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    document_type: Mapped[DocumentType] = enum_column(DocumentType, nullable=False)
    ocr_mode: Mapped[OcrMode] = enum_column(OcrMode, nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="uploaded", nullable=False, index=True)
    file_name: Mapped[str | None] = mapped_column(String(255))
    mime_type: Mapped[str | None] = mapped_column(String(120))
    size_bytes: Mapped[int | None] = mapped_column(Integer)
    storage_url: Mapped[str | None] = mapped_column(Text)
    client_request_id: Mapped[str] = mapped_column(String(128), index=True)
    job_id: Mapped[str | None] = mapped_column(ForeignKey("jobs.id"), index=True)
    raw_text: Mapped[str | None] = mapped_column(Text)
    draft_payload: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    confirmed_by_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    nurse_note: Mapped[str | None] = mapped_column(Text)


class Medication(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "medications"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    document_id: Mapped[str | None] = mapped_column(ForeignKey("medical_documents.id"), index=True)
    name: Mapped[str] = mapped_column(String(255), index=True)
    strength: Mapped[str | None] = mapped_column(String(120))
    dosage: Mapped[str | None] = mapped_column(String(255))
    frequency: Mapped[str | None] = mapped_column(String(255))
    times_of_day: Mapped[list[str] | None] = mapped_column(JSON)
    instructions: Mapped[str | None] = mapped_column(Text)
    start_date: Mapped[date | None] = mapped_column(Date)
    end_date: Mapped[date | None] = mapped_column(Date)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)

    patient: Mapped[Patient] = relationship(back_populates="medications")


class Appointment(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "appointments"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    appointment_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    department: Mapped[str | None] = mapped_column(String(255))
    doctor_name: Mapped[str | None] = mapped_column(String(255))
    status: Mapped[str | None] = mapped_column(String(32), default="scheduled", index=True)

    patient: Mapped[Patient] = relationship(back_populates="appointments")


class Checkin(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "checkins"
    __table_args__ = (UniqueConstraint("patient_id", "scheduled_for", name="uq_checkins_patient_day"),)

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    scheduled_for: Mapped[date] = mapped_column(Date, index=True)
    status: Mapped[str] = mapped_column(String(32), default="ready", nullable=False, index=True)
    question_text: Mapped[str] = mapped_column(Text)
    audio_status: Mapped[AudioStatus] = enum_column(AudioStatus, default=AudioStatus.unavailable)
    audio_url: Mapped[str | None] = mapped_column(Text)
    audio_cache_key: Mapped[str | None] = mapped_column(String(255))
    tts_job_id: Mapped[str | None] = mapped_column(ForeignKey("jobs.id"))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class CheckinResponse(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "checkin_responses"
    __table_args__ = (
        UniqueConstraint("checkin_id", "client_request_id", name="uq_checkin_response_request"),
    )

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    checkin_id: Mapped[str] = mapped_column(ForeignKey("checkins.id"), index=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    quick_answer_id: Mapped[str | None] = mapped_column(String(32))
    audio_url: Mapped[str | None] = mapped_column(Text)
    recorded_duration_seconds: Mapped[int | None] = mapped_column(Integer)
    client_recorded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    client_request_id: Mapped[str] = mapped_column(String(128), index=True)
    status: Mapped[JobStatus] = enum_column(JobStatus, default=JobStatus.queued, index=True)
    job_id: Mapped[str | None] = mapped_column(ForeignKey("jobs.id"), index=True)
    transcript: Mapped[str | None] = mapped_column(Text)
    summary: Mapped[str | None] = mapped_column(Text)
    risk_level: Mapped[RiskLevel | None] = enum_column(RiskLevel, nullable=True, index=True)
    risk_reasons: Mapped[list[str] | None] = mapped_column(JSON)
    needs_staff_review: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    handling_status: Mapped[HandlingStatus | None] = enum_column(HandlingStatus, nullable=True)
    staff_alert_id: Mapped[str | None] = mapped_column(String(40), index=True)


class StaffAlert(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "staff_alerts"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    source_type: Mapped[TimelineEntryType] = enum_column(TimelineEntryType, nullable=False)
    source_id: Mapped[str] = mapped_column(String(40), index=True)
    risk_level: Mapped[RiskLevel] = enum_column(RiskLevel, nullable=False, index=True)
    summary: Mapped[str | None] = mapped_column(Text)
    handling_status: Mapped[HandlingStatus] = enum_column(
        HandlingStatus, default=HandlingStatus.new, nullable=False, index=True
    )
    unread: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
    handled_by_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    handled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    handling_note: Mapped[str | None] = mapped_column(Text)
    callback_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class HotlineQuestion(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "hotline_questions"
    __table_args__ = (
        UniqueConstraint("patient_id", "client_request_id", name="uq_hotline_patient_request"),
    )

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    asked_by_user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    mode: Mapped[str] = mapped_column(String(16), index=True)
    question_text: Mapped[str | None] = mapped_column(Text)
    audio_url: Mapped[str | None] = mapped_column(Text)
    recorded_duration_seconds: Mapped[int | None] = mapped_column(Integer)
    client_request_id: Mapped[str] = mapped_column(String(128), index=True)
    status: Mapped[JobStatus] = enum_column(JobStatus, default=JobStatus.queued, index=True)
    job_id: Mapped[str | None] = mapped_column(ForeignKey("jobs.id"), index=True)
    transcript: Mapped[str | None] = mapped_column(Text)
    answer_text: Mapped[str | None] = mapped_column(Text)
    source_scope: Mapped[str | None] = mapped_column(String(120))
    needs_staff_review: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    risk_level: Mapped[RiskLevel | None] = enum_column(RiskLevel, nullable=True, index=True)
    staff_alert_id: Mapped[str | None] = mapped_column(String(40), index=True)


class Device(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "devices"
    __table_args__ = (UniqueConstraint("device_id", "user_id", name="uq_devices_device_user"),)

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    device_id: Mapped[str] = mapped_column(String(255), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    device_token: Mapped[str | None] = mapped_column(Text)
    platform: Mapped[str] = mapped_column(String(32), default="ios")
    push_environment: Mapped[PushEnvironment] = enum_column(PushEnvironment, default=PushEnvironment.sandbox)
    role: Mapped[UserRole] = enum_column(UserRole, nullable=False)
    app_version: Mapped[str | None] = mapped_column(String(64))
    os_version: Mapped[str | None] = mapped_column(String(64))
    locale: Mapped[str | None] = mapped_column(String(32))
    checkin_reminders_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    medication_reminders_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    appointment_reminders_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    critical_staff_alerts_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)


class FaceVerificationSession(Base, TimestampMixin, SoftDeleteMixin, VersionMixin):
    __tablename__ = "face_verification_sessions"

    id: Mapped[str] = mapped_column(String(40), primary_key=True)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.id"), index=True)
    requested_by_user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    purpose: Mapped[str] = mapped_column(String(80))
    status: Mapped[str] = mapped_column(String(32), default="not_started", nullable=False)
    upload_url: Mapped[str | None] = mapped_column(Text)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    needs_staff_review: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)


Index("ix_priority_patients", Patient.latest_risk_level, Patient.latest_checkin_at)
Index("ix_alerts_priority", StaffAlert.handling_status, StaffAlert.risk_level, StaffAlert.created_at)

