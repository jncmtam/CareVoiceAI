from datetime import datetime

from app.models.enums import HandlingStatus, JobStatus, RiskLevel, TimelineEntryType
from app.schemas.common import APIModel
from app.schemas.patients import PatientSummary


class DashboardOverview(APIModel):
    total_active_patients: int
    needs_attention_today: int
    needs_intervention_today: int
    checkin_completion_rate: float
    pending_ocr_jobs: int | None = None
    pending_analysis_jobs: int | None = None
    updated_at: datetime | None = None


class PriorityPatientListResponse(APIModel):
    items: list[PatientSummary]
    page: int
    per_page: int
    total: int
    has_next: bool


class TimelinePatientHeader(APIModel):
    id: str
    patient_code: str
    full_name: str
    age: int | None = None
    latest_risk_level: RiskLevel | None = None
    alert_reasons: list[str] | None = None
    caregiver_alert_sent_at: datetime | None = None
    missed_medication_doses: int | None = None


class TimelineEntry(APIModel):
    id: str
    type: TimelineEntryType
    occurred_at: datetime
    status: JobStatus
    risk_level: RiskLevel | None = None
    summary: str | None = None
    transcript: str | None = None
    risk_reasons: list[str] | None = None
    handling_status: HandlingStatus | None = None
    staff_alert_id: str | None = None
    staff_note: str | None = None
    handled_by_name: str | None = None
    display_message: str | None = None
    job_id: str | None = None
    audio_url: str | None = None
    quick_answer_id: str | None = None
    patient_declared_risk_level: RiskLevel | None = None
    recorded_duration_seconds: int | None = None
    analysis_hints: list[str] | None = None


class PatientTimelineResponse(APIModel):
    patient: TimelinePatientHeader
    items: list[TimelineEntry]
    next_cursor: str | None = None


class HandlingUpdateRequest(APIModel):
    handling_status: HandlingStatus
    note: str | None = None
    callback_at: datetime | None = None


class HandledByUser(APIModel):
    id: str
    full_name: str


class HandlingUpdateResponse(APIModel):
    entry_id: str
    handling_status: HandlingStatus
    handled_by: HandledByUser | None = None
    handled_at: datetime | None = None
    note: str | None = None


class StaffNotificationItem(APIModel):
    id: str
    patient_id: str
    patient_name: str
    patient_code: str | None = None
    notification_type: str
    previous_risk_level: RiskLevel | None = None
    new_risk_level: RiskLevel
    source_type: str | None = None
    source_id: str | None = None
    title: str
    message: str
    unread: bool
    created_at: datetime
    read_at: datetime | None = None


class StaffNotificationListResponse(APIModel):
    items: list[StaffNotificationItem]
    unread_count: int
    page: int
    per_page: int
    total: int
    has_next: bool


class StaffNotificationReadResponse(APIModel):
    id: str
    unread: bool
    read_at: datetime | None = None


class StaffNotificationMarkAllReadResponse(APIModel):
    updated_count: int

