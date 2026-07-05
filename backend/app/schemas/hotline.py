from datetime import datetime

from pydantic import Field

from app.models.enums import JobStatus, RiskLevel
from app.schemas.common import APIModel


class HotlineQuestionTextRequest(APIModel):
    mode: str = Field(pattern="^text$")
    patient_id: str | None = None
    text: str = Field(min_length=1, max_length=2000)
    client_request_id: str = Field(min_length=1, max_length=128)


class HotlineQuestionResponse(APIModel):
    question_id: str
    job_id: str | None = None
    status: JobStatus
    transcript: str | None = None
    answer_text: str | None = None
    source_scope: str | None = None
    needs_staff_review: bool | None = None
    risk_level: RiskLevel | None = None
    reasons: list[str] | None = None
    staff_alert_id: str | None = None
    poll_after_seconds: float | None = None


class HotlineQuestionStatusResponse(APIModel):
    question_id: str
    status: JobStatus
    transcript: str | None = None
    answer_text: str | None = None
    needs_staff_review: bool | None = None
    risk_level: RiskLevel | None = None
    reasons: list[str] | None = None
    staff_alert_id: str | None = None
    poll_after_seconds: float | None = None


class HotlineHistoryItem(APIModel):
    question_id: str
    asked_at: datetime
    mode: str | None = None
    question_text: str | None = None
    transcript: str | None = None
    answer_text: str | None = None
    needs_staff_review: bool | None = None
    risk_level: RiskLevel | None = None
    reasons: list[str] | None = None


class HotlineHistoryResponse(APIModel):
    items: list[HotlineHistoryItem]
    next_cursor: str | None = None