from datetime import timedelta

from app.integrations.vnpt.daily_tip import daily_tip_fallback, daily_tip_prompt
from app.integrations.vnpt.parsers.prescription import parse_ocr_payload
from app.integrations.vnpt.types import HotlineAnswer, OcrResult, SpeechResult, TtsResult
from app.models.enums import RiskLevel
from app.services.risk_classifier import classify_transcript, merge_risk_levels
from app.utils.datetime import now_utc
from app.utils.document_text import extract_document_text

_DEFAULT_RAW_TEXT = (
    "Bệnh nhân: Chu Minh Tâm. SĐT: 0327628468. Chẩn đoán: Đái tháo đường type 2, Tăng huyết áp.\n"
    "Bác sĩ: BS. Lê Minh. Metformin 500mg ngày 2 lần. Amlodipine 5mg mỗi sáng.\n"
    "Tái khám Nội tiết sau 14 ngày. Dặn dò: Uống thuốc đủ liều, không tự ý ngưng thuốc."
)


class MockVNPTGateway:
    async def scan_medical_document(
        self,
        *,
        file_url: str | None,
        mode: str,
        file_bytes: bytes | None = None,
        filename: str | None = None,
        content_type: str | None = None,
        document_type: str = "prescription",
    ) -> tuple[OcrResult, str | None]:
        _ = (file_url, mode, document_type)
        raw_text = _DEFAULT_RAW_TEXT
        if file_bytes:
            extracted = extract_document_text(
                file_bytes=file_bytes,
                filename=filename or "",
                content_type=content_type,
            )
            if extracted.strip():
                raw_text = extracted

        parsed = parse_ocr_payload(raw_text=raw_text)
        follow_up = dict(parsed.draft_follow_up or {})
        if follow_up.get("appointment_at") is None and "ngày" in raw_text.lower():
            follow_up["appointment_at"] = (now_utc() + timedelta(days=14)).isoformat()

        return (
            OcrResult(
                raw_text=parsed.raw_text,
                draft_patient=parsed.draft_patient,
                draft_medications=parsed.draft_medications,
                draft_follow_up=follow_up or None,
                instructions=parsed.instructions,
                warnings=parsed.warnings,
            ),
            None,
        )

    _HOTLINE_SAMPLE_TRANSCRIPTS = (
        "Hôm nay tôi thấy bình thường, không đau ngực hay khó thở.",
        "Tôi quên uống thuốc sáng nay thì có uống bù không?",
        "Tôi thấy đau ngực và khó thở, có nên uống thuốc không?",
    )

    async def transcribe_audio(
        self,
        *,
        file_url: str | None,
        fallback_text: str | None = None,
        file_bytes: bytes | None = None,
        filename: str | None = None,
        content_type: str | None = None,
        duration_seconds: int | None = None,
    ) -> SpeechResult:
        _ = (file_url, filename, content_type)
        if fallback_text:
            return SpeechResult(transcript=fallback_text)
        index = 0
        if file_bytes:
            index = len(file_bytes) % len(self._HOTLINE_SAMPLE_TRANSCRIPTS)
        elif duration_seconds:
            index = duration_seconds % len(self._HOTLINE_SAMPLE_TRANSCRIPTS)
        return SpeechResult(transcript=self._HOTLINE_SAMPLE_TRANSCRIPTS[index])

    async def synthesize_question(
        self,
        *,
        text: str,
        checkin_id: str,
        media_base_url: str,
        save_audio: object | None = None,
    ) -> TtsResult:
        _ = (text, save_audio)
        return TtsResult(
            audio_url=f"{media_base_url.rstrip('/')}/media/tts/{checkin_id}.m4a",
            audio_cache_key=f"tts_{checkin_id}_v1",
        )

    async def answer_hotline(
        self,
        *,
        text: str,
        has_confirmed_record: bool,
        sender_id: str = "patient",
        session_id: str = "default",
    ) -> dict:
        _ = (sender_id, session_id)
        answer = await self._answer(text, has_confirmed_record)
        return {
            "answer_text": answer.answer_text,
            "source_scope": answer.source_scope,
            "needs_staff_review": answer.needs_staff_review,
            "risk_level": answer.risk_level,
            "reasons": answer.reasons,
        }

    async def cancel_ocr(self, vendor_job_id: str | None) -> None:
        _ = vendor_job_id

    async def daily_health_tip(
        self,
        *,
        diagnoses: list[str],
        medications: list[str],
        patient_id: str,
        tip_date: str,
    ) -> tuple[str, str]:
        _ = daily_tip_prompt(diagnoses=diagnoses, medications=medications, tip_date=tip_date)
        return daily_tip_fallback(diagnoses, patient_id, tip_date), "mock_fallback"

    async def _answer(self, text: str, has_confirmed_record: bool) -> HotlineAnswer:
        level, reasons = classify_transcript(text, source="hotline")
        if level == RiskLevel.intervention:
            return HotlineAnswer(
                answer_text="Triệu chứng này cần điều dưỡng/bác sĩ xem lại ngay. Hệ thống đã gửi cảnh báo.",
                source_scope="safety_guardrail",
                needs_staff_review=True,
                risk_level=level.value,
                reasons=reasons[:3],
            )
        lowered = text.lower()
        normal_terms = ["bình thường", "không đau", "không khó thở", "ổn"]
        if has_confirmed_record and level == RiskLevel.normal and any(term in lowered for term in normal_terms):
            return HotlineAnswer(
                answer_text=(
                    "Cảm ơn bác đã cập nhật. Bác tiếp tục uống thuốc đúng giờ "
                    "và check-in hàng ngày."
                ),
                source_scope="confirmed_medical_record",
                needs_staff_review=False,
                risk_level=level.value,
                reasons=reasons,
            )
        if not has_confirmed_record:
            return HotlineAnswer(
                answer_text=(
                    "Hệ thống chưa có đủ hồ sơ đã xác nhận. "
                    "Bác vui lòng liên hệ điều dưỡng để được hướng dẫn."
                ),
                source_scope="insufficient_confirmed_record",
                needs_staff_review=True,
                risk_level=merge_risk_levels(level, RiskLevel.attention).value,
                reasons=reasons[:3] or ["Chưa có hồ sơ thuốc đã xác nhận"],
            )
        fallback_level = merge_risk_levels(level, RiskLevel.attention)
        return HotlineAnswer(
            answer_text=(
                "Bác không tự ý thay đổi liều. Bác vui lòng làm theo đơn đã xác nhận "
                "và liên hệ điều dưỡng nếu triệu chứng thay đổi."
            ),
            source_scope="confirmed_medical_record",
            needs_staff_review=True,
            risk_level=fallback_level.value,
            reasons=reasons[:3]
            if level != RiskLevel.normal
            else ["Câu hỏi liên quan hướng dẫn dùng thuốc cần nhân viên y tế xác nhận."],
        )