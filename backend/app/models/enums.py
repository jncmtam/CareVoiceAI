from enum import Enum


class UserRole(str, Enum):
    patient = "patient"
    caregiver = "caregiver"
    nurse = "nurse"
    doctor = "doctor"
    admin = "admin"


class RiskLevel(str, Enum):
    normal = "normal"
    attention = "attention"
    intervention = "intervention"


class JobStatus(str, Enum):
    queued = "queued"
    uploading = "uploading"
    processing = "processing"
    transcribing = "transcribing"
    analyzing = "analyzing"
    summarizing = "summarizing"
    needs_review = "needs_review"
    completed = "completed"
    failed = "failed"
    cancelled = "cancelled"
    expired = "expired"


class AudioStatus(str, Enum):
    ready = "ready"
    generating = "generating"
    unavailable = "unavailable"
    failed = "failed"


class DocumentType(str, Enum):
    prescription = "prescription"
    discharge_note = "discharge_note"


class OcrMode(str, Enum):
    auto = "auto"
    basic = "basic"
    table = "table"


class HandlingStatus(str, Enum):
    new = "new"
    viewed = "viewed"
    called_back = "called_back"
    resolved = "resolved"


class TimelineEntryType(str, Enum):
    checkin_response = "checkin_response"
    hotline_question = "hotline_question"
    medication_update = "medication_update"
    appointment = "appointment"


class PushEnvironment(str, Enum):
    sandbox = "sandbox"
    production = "production"


class Gender(str, Enum):
    male = "male"
    female = "female"
    other = "other"


class MedicationTimeOfDay(str, Enum):
    morning = "morning"
    noon = "noon"
    afternoon = "afternoon"
    evening = "evening"
    bedtime = "bedtime"


class JobType(str, Enum):
    ocr = "ocr"
    checkin_analysis = "checkin_analysis"
    hotline = "hotline"
    tts = "tts"
    face_verification = "face_verification"

