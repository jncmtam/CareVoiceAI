from dataclasses import dataclass


@dataclass(frozen=True)
class OcrResult:
    raw_text: str
    draft_medications: list[dict]
    draft_follow_up: dict | None
    draft_patient: dict | None = None
    instructions: str | None = None
    warnings: list[str] | None = None


@dataclass(frozen=True)
class SpeechResult:
    transcript: str


@dataclass(frozen=True)
class TtsResult:
    audio_url: str
    audio_cache_key: str


@dataclass(frozen=True)
class HotlineAnswer:
    answer_text: str
    source_scope: str
    needs_staff_review: bool
    risk_level: str
    reasons: list[str]