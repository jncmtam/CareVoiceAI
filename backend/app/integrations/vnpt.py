from dataclasses import dataclass


@dataclass(frozen=True)
class OcrResult:
    raw_text: str
    draft_medications: list[dict]
    draft_follow_up: dict | None
    warnings: list[str]


@dataclass(frozen=True)
class SpeechResult:
    transcript: str


@dataclass(frozen=True)
class TtsResult:
    audio_url: str
    audio_cache_key: str


class VNPTGateway:
    """Boundary for VNPT services.

    The mock implementation keeps the backend usable in local/demo environments.
    Production should replace these methods with HTTP calls to SmartReader,
    SmartVoice, STT and SmartBot while preserving the same service contract.
    """

    async def scan_medical_document(self, *, file_url: str | None, mode: str) -> OcrResult:
        return OcrResult(
            raw_text="Metformin 500mg ngày 2 lần. Amlodipine 5mg mỗi sáng. Tái khám Nội tiết sau 14 ngày.",
            draft_medications=[
                {
                    "name": "Metformin",
                    "strength": "500mg",
                    "dosage": "1 viên",
                    "frequency": "2 lần/ngày",
                    "times_of_day": ["morning", "evening"],
                    "instructions": "Uống sau ăn",
                    "confidence": 0.91,
                },
                {
                    "name": "Amlodipine",
                    "strength": "5mg",
                    "dosage": "1 viên",
                    "frequency": "Mỗi sáng",
                    "times_of_day": ["morning"],
                    "instructions": "Uống vào cùng một giờ mỗi ngày",
                    "confidence": 0.86,
                },
            ],
            draft_follow_up={
                "department": "Nội tiết",
                "doctor_name": "BS. Lê Minh",
                "appointment_at": None,
            },
            warnings=["Kiểm tra lại hàm lượng thuốc trước khi xác nhận."],
        )

    async def transcribe_audio(self, *, file_url: str | None, fallback_text: str | None = None) -> SpeechResult:
        return SpeechResult(
            transcript=fallback_text
            or "Hôm nay tôi thấy bình thường, không đau ngực hay khó thở."
        )

    async def synthesize_question(self, *, text: str, checkin_id: str, media_base_url: str) -> TtsResult:
        return TtsResult(
            audio_url=f"{media_base_url.rstrip('/')}/media/tts/{checkin_id}.m4a",
            audio_cache_key=f"tts_{checkin_id}_v1",
        )

    async def answer_hotline(self, *, text: str, has_confirmed_record: bool) -> dict:
        danger_terms = ["đau ngực", "khó thở", "ngất", "co giật"]
        intervention = any(term in text.lower() for term in danger_terms)
        if intervention:
            return {
                "answer_text": "Triệu chứng này cần điều dưỡng/bác sĩ xem lại. Hệ thống đã gửi cảnh báo.",
                "source_scope": "safety_guardrail",
                "needs_staff_review": True,
                "risk_level": "intervention",
                "reasons": ["Câu hỏi có dấu hiệu cảnh báo cần can thiệp"],
            }
        if not has_confirmed_record:
            return {
                "answer_text": (
                    "Hệ thống chưa có đủ hồ sơ đã xác nhận. "
                    "Bác vui lòng liên hệ điều dưỡng để được hướng dẫn."
                ),
                "source_scope": "insufficient_confirmed_record",
                "needs_staff_review": True,
                "risk_level": "attention",
                "reasons": ["Chưa có hồ sơ thuốc đã xác nhận"],
            }
        return {
            "answer_text": (
                "Bác không tự ý thay đổi liều. Bác vui lòng làm theo đơn đã xác nhận "
                "và liên hệ điều dưỡng nếu triệu chứng thay đổi."
            ),
            "source_scope": "confirmed_medical_record",
            "needs_staff_review": True,
            "risk_level": "attention",
            "reasons": ["Câu hỏi liên quan hướng dẫn dùng thuốc cần nhân viên y tế xác nhận"],
        }


vnpt_gateway = VNPTGateway()
