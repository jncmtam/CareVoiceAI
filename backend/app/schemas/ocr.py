from datetime import datetime

from pydantic import Field

from app.models.enums import JobStatus, MedicationTimeOfDay
from app.schemas.common import APIModel
from app.schemas.patients import FollowUpDraft, MedicalDocument, Medication, OCRPatientDraft


class DocumentUploadResponse(APIModel):
    upload_id: str
    job_id: str
    status: JobStatus
    poll_after_seconds: float | None = None
    message: str | None = None


class OCRDraftMedication(APIModel):
    name: str
    strength: str | None = None
    dosage: str | None = None
    frequency: str | None = None
    times_of_day: list[MedicationTimeOfDay] | None = None
    instructions: str | None = None
    confidence: float | None = Field(default=None, ge=0, le=1)


class OCRJobResponse(APIModel):
    job_id: str
    upload_id: str | None = None
    patient_id: str | None = None
    status: JobStatus
    progress: int | None = None
    stage: str | None = None
    poll_after_seconds: float | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    raw_text: str | None = None
    draft_medications: list[OCRDraftMedication] | None = None
    draft_patient: OCRPatientDraft | None = None
    draft_follow_up: FollowUpDraft | None = None
    instructions: str | None = None
    warnings: list[str] | None = None


class CancelJobRequest(APIModel):
    reason: str | None = None


class CancelJobResponse(APIModel):
    job_id: str
    status: JobStatus


class OCRConfirmRequest(APIModel):
    job_id: str
    confirmed_by_user_id: str | None = None
    medications: list[Medication]
    follow_up: FollowUpDraft | None = None
    patient_draft: OCRPatientDraft | None = None
    instructions: str | None = None
    nurse_note: str | None = None


class OCRConfirmResponse(APIModel):
    document: MedicalDocument
    medications: list[Medication]
