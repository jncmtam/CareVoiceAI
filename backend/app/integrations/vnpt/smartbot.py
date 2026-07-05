from __future__ import annotations

from typing import Any

from app.core.config import Settings
from app.core.errors import APIError
from app.models.enums import RiskLevel
from app.integrations.vnpt.auth import VNPTAuthService
from app.integrations.vnpt.client import VNPTHttpClient, extract_object
from app.integrations.vnpt.types import HotlineAnswer
from app.services.risk_classifier import classify_transcript, merge_risk_levels


class SmartBotClient:
    def __init__(self, settings: Settings, http: VNPTHttpClient, auth: VNPTAuthService) -> None:
        self.settings = settings
        self.http = http
        self.auth = auth

    async def answer_hotline(
        self,
        *,
        text: str,
        has_confirmed_record: bool,
        sender_id: str,
        session_id: str,
    ) -> HotlineAnswer:
        guardrail = self._guardrail_answer(text, has_confirmed_record)
        if guardrail:
            return guardrail
        if not self.settings.vnpt_smartbot_bot_id:
            return self._fallback_answer(text, has_confirmed_record)

        try:
            access_token = await self.auth.access_token("smartbot")
            payload = await self.http.request_sse_json(
                method="POST",
                base_url=self.settings.vnpt_smartbot_base_url,
                path="v1/conversation",
                token_id=self.settings.vnpt_token_id_for("smartbot"),
                token_key=self.settings.vnpt_token_key_for("smartbot"),
                access_token=access_token,
                json_body={
                    "bot_id": self.settings.vnpt_smartbot_bot_id,
                    "sender_id": sender_id,
                    "text": text,
                    "input_channel": self.settings.vnpt_smartbot_input_channel,
                    "session_id": session_id,
                    "metadata": {"button_variables": self._button_variables(has_confirmed_record)},
                },
                include_mac=False,
            )
        except (APIError, ValueError):
            return self._fallback_answer(text, has_confirmed_record)
        answer_text = self._extract_answer_text(payload)
        needs_review = self._needs_staff_review(payload) or True
        if not answer_text:
            return self._fallback_answer(text, has_confirmed_record)

        classified_level, classified_reasons = classify_transcript(text, source="hotline")
        risk_level = classified_level.value
        reasons = classified_reasons
        if needs_review and classified_level == RiskLevel.normal:
            risk_level = "attention"
            reasons = ["Câu hỏi cần nhân viên y tế xác nhận nếu liên quan điều trị."]
        return HotlineAnswer(
            answer_text=answer_text,
            source_scope="confirmed_medical_record" if has_confirmed_record else "smartbot",
            needs_staff_review=needs_review or classified_level != RiskLevel.normal,
            risk_level=risk_level,
            reasons=reasons,
        )

    def _extract_answer_text(self, payload: dict[str, Any]) -> str:
        obj = extract_object(payload)
        sb = obj.get("sb") if isinstance(obj.get("sb"), dict) else {}
        cards = sb.get("card_data") or obj.get("card_data") or []
        texts: list[str] = []
        if isinstance(cards, list):
            for card in cards:
                if not isinstance(card, dict):
                    continue
                if card.get("type") == "chuyen_gdv":
                    texts.append("Hệ thống đang chuyển sang điều dưỡng hỗ trợ.")
                    continue
                value = (
                    card.get("text")
                    or card.get("process_content")
                    or card.get("value")
                    or card.get("title")
                )
                if value:
                    texts.append(str(value).strip())
        if texts:
            return "\n".join(texts)
        fallback = str(obj.get("answer_text") or obj.get("message") or payload.get("message") or "").strip()
        if fallback.startswith("IDG-"):
            return ""
        return fallback

    def _needs_staff_review(self, payload: dict[str, Any]) -> bool:
        obj = extract_object(payload)
        sb = obj.get("sb") if isinstance(obj.get("sb"), dict) else {}
        cards = sb.get("card_data") or []
        if isinstance(cards, list):
            return any(isinstance(card, dict) and card.get("type") == "chuyen_gdv" for card in cards)
        return False

    def _button_variables(self, has_confirmed_record: bool) -> list[dict[str, str]]:
        return [
            {
                "variableName": "has_confirmed_record",
                "value": "true" if has_confirmed_record else "false",
            }
        ]

    def _guardrail_answer(self, text: str, has_confirmed_record: bool) -> HotlineAnswer | None:
        level, reasons = classify_transcript(text, source="hotline")
        if level == RiskLevel.intervention:
            return HotlineAnswer(
                answer_text="Triệu chứng này cần điều dưỡng/bác sĩ xem lại ngay. Hệ thống đã gửi cảnh báo.",
                source_scope="safety_guardrail",
                needs_staff_review=True,
                risk_level=level.value,
                reasons=reasons[:3] or ["Câu hỏi có dấu hiệu cảnh báo cần can thiệp"],
            )
        if not has_confirmed_record:
            return HotlineAnswer(
                answer_text=(
                    "Hệ thống chưa có đủ hồ sơ đã xác nhận. "
                    "Bác vui lòng liên hệ điều dưỡng để được hướng dẫn."
                ),
                source_scope="insufficient_confirmed_record",
                needs_staff_review=True,
                risk_level="attention",
                reasons=["Chưa có hồ sơ thuốc đã xác nhận"],
            )
        return None

    async def daily_health_tip(
        self,
        *,
        prompt: str,
        sender_id: str,
        session_id: str,
    ) -> str:
        if not self.settings.vnpt_smartbot_bot_id:
            return ""
        try:
            access_token = await self.auth.access_token("smartbot")
            payload = await self.http.request_sse_json(
                method="POST",
                base_url=self.settings.vnpt_smartbot_base_url,
                path="v1/conversation",
                token_id=self.settings.vnpt_token_id_for("smartbot"),
                token_key=self.settings.vnpt_token_key_for("smartbot"),
                access_token=access_token,
                json_body={
                    "bot_id": self.settings.vnpt_smartbot_bot_id,
                    "sender_id": sender_id,
                    "text": prompt,
                    "input_channel": self.settings.vnpt_smartbot_input_channel,
                    "session_id": session_id,
                    "metadata": {"button_variables": []},
                },
                include_mac=False,
            )
        except (APIError, ValueError):
            return ""
        answer = self._extract_answer_text(payload).strip()
        if not answer or answer.startswith("IDG-"):
            return ""
        return answer[:500]

    def _fallback_answer(self, text: str, has_confirmed_record: bool) -> HotlineAnswer:
        guardrail = self._guardrail_answer(text, has_confirmed_record)
        if guardrail:
            return guardrail
        level, reasons = classify_transcript(text, source="hotline")
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
