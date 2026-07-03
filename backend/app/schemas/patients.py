from datetime import date, datetime

from pydantic import Field

from app.models.enums import DocumentType, Gender, MedicationTimeOfDay, RiskLevel
from app.schemas.common import APIModel


class PatientCreateRequest(APIModel):
    patient_code: str = Field(min_length=1, max_length=64)
    full_name: str = Field(min_length=1, max_length=255)
    date_of_birth: date | None = None
    gender: Gender | None = None
    phone_number: str = Field(min_length=8, max_length=32)
    caregiver_name: str | None = None
    caregiver_phone_number: str | None = None
    diagnoses: list[str] = Field(default_factory=list)
    address: str | None = None
    primary_doctor_name: str | None = None
    notes: str | None = None


class PatientUpdateRequest(APIModel):
    phone_number: str | None = Field(default=None, min_length=8, max_length=32)
    caregiver_phone_number: str | None = None
    notes: str | None = None


class PatientProfile(APIModel):
    id: str
    patient_code: str
    full_name: str
    date_of_birth: date | None = None
    gender: Gender | None = None
    phone_number: str | None = None
    caregiver_name: str | None = None
    caregiver_phone_number: str | None = None
    diagnoses: list[str] | None = None
    latest_risk_level: RiskLevel | None = None
    latest_checkin_at: datetime | None = None
    next_appointment_at: datetime | None = None
    notes: str | None = None
    age: int | None = None
    is_active: bool | None = None


class PatientResponse(APIModel):
    patient: PatientProfile


class PatientSummary(APIModel):
    patient_id: str
    patient_code: str
    full_name: str
    age: int | None = None
    diagnoses: list[str] | None = None
    latest_risk_level: RiskLevel | None = None
    latest_summary: str | None = None
    latest_checkin_at: datetime | None = None
    handling_status: str | None = None
    unread_alert_count: int | None = None


class Medication(APIModel):
    id: str | None = None
    name: str
    strength: str | None = None
    dosage: str | None = None
    frequency: str | None = None
    times_of_day: list[MedicationTimeOfDay] | None = None
    instructions: str | None = None
    start_date: date | None = None
    end_date: date | None = None
    is_active: bool | None = None


class MedicationListResponse(APIModel):
    medications: list[Medication]


class FollowUpDraft(APIModel):
    appointment_at: datetime | None = None
    department: str | None = None
    doctor_name: str | None = None


class Appointment(APIModel):
    id: str
    appointment_at: datetime
    department: str | None = None
    doctor_name: str | None = None
    status: str | None = None


class AppointmentListResponse(APIModel):
    appointments: list[Appointment]


class MedicalDocument(APIModel):
    id: str
    document_type: DocumentType
    status: str
    confirmed_at: datetime | None = None

