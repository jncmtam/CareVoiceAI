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
    display_message: str | None = None
    job_id: str | None = None


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

