from datetime import date, datetime

from app.models.enums import AudioStatus, JobStatus, RiskLevel
from app.schemas.common import APIModel


class QuickAnswer(APIModel):
    id: str
    label: str


class Checkin(APIModel):
    id: str
    patient_id: str | None = None
    scheduled_for: date | str | None = None
    status: str
    completed_job_id: str | None = None
    question_text: str
    audio_status: AudioStatus
    audio_url: str | None = None
    audio_cache_key: str | None = None
    tts_job_id: str | None = None
    poll_after_seconds: float | None = None
    quick_answers: list[QuickAnswer]
    expires_at: datetime | None = None


class TodayCheckinResponse(APIModel):
    checkin: Checkin


class CheckinAudioStatusResponse(APIModel):
    checkin_id: str
    audio_status: AudioStatus
    audio_url: str | None = None
    audio_cache_key: str | None = None
    poll_after_seconds: float | None = None


class CheckinTranscribeResponse(APIModel):
    transcript: str
    suggested_risk_level: RiskLevel | None = None
    message: str | None = None


class SubmitCheckinResponse(APIModel):
    response_id: str
    job_id: str
    status: JobStatus
    poll_after_seconds: float | None = None
    message: str | None = None


class RiskAssessment(APIModel):
    level: RiskLevel
    label: str | None = None
    reasons: list[str] | None = None
    analysis_hints: list[str] | None = None
    needs_staff_review: bool


class CheckinJobResponse(APIModel):
    job_id: str
    response_id: str | None = None
    status: JobStatus
    progress: int | None = None
    stage: str | None = None
    display_message: str | None = None
    poll_after_seconds: float | None = None
    transcript: str | None = None
    summary: str | None = None
    risk: RiskAssessment | None = None
    staff_alert_id: str | None = None
    caregiver_alert_sent_at: datetime | None = None
    completed_at: datetime | None = None


class CheckinHistoryItem(APIModel):
    id: str
    checked_in_at: datetime
    status: str
    risk_level: RiskLevel | None = None
    patient_message: str | None = None
    summary_for_patient: str | None = None
    staff_note: str | None = None


class CheckinHistoryResponse(APIModel):
    items: list[CheckinHistoryItem]
    next_cursor: str | None = None

