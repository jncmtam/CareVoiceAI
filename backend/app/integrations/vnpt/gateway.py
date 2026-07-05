from __future__ import annotations

from typing import Any, Protocol

from app.core.config import Settings
from app.integrations.vnpt.auth import VNPTAuthService
from app.integrations.vnpt.client import VNPTHttpClient
from app.integrations.vnpt.smartbot import SmartBotClient
from app.integrations.vnpt.smartreader import SmartReaderClient
from app.integrations.vnpt.smartvoice import SmartVoiceClient
from app.integrations.vnpt.types import OcrResult, SpeechResult, TtsResult


class VNPTGateway(Protocol):
    async def scan_medical_document(
        self,
        *,
        file_url: str | None,
        mode: str,
        file_bytes: bytes | None = None,
        filename: str | None = None,
        content_type: str | None = None,
        document_type: str = "prescription",
    ) -> tuple[OcrResult, str | None]: ...

    async def transcribe_audio(
        self,
        *,
        file_url: str | None,
        fallback_text: str | None = None,
        file_bytes: bytes | None = None,
        filename: str | None = None,
        content_type: str | None = None,
        duration_seconds: int | None = None,
    ) -> SpeechResult: ...

    async def synthesize_question(
        self,
        *,
        text: str,
        checkin_id: str,
        media_base_url: str,
        save_audio: Any | None = None,
    ) -> TtsResult: ...

    async def answer_hotline(
        self,
        *,
        text: str,
        has_confirmed_record: bool,
        sender_id: str = "patient",
        session_id: str = "default",
    ) -> dict: ...

    async def cancel_ocr(self, vendor_job_id: str | None) -> None: ...


class LiveVNPTGateway:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.http = VNPTHttpClient(settings)
        self.auth = VNPTAuthService(settings, self.http)
        self.reader = SmartReaderClient(settings, self.http, self.auth)
        self.voice = SmartVoiceClient(settings, self.http, self.auth)
        self.bot = SmartBotClient(settings, self.http, self.auth)

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
        _ = (file_url, document_type)
        if not file_bytes:
            raise ValueError("file_bytes is required for live OCR.")
        return await self.reader.scan_medical_document(
            file_bytes=file_bytes,
            filename=filename or "document.pdf",
            content_type=content_type or "application/octet-stream",
            mode=mode,
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
        _ = file_url
        return await self.voice.transcribe_audio(
            file_bytes=file_bytes,
            filename=filename,
            content_type=content_type,
            duration_seconds=duration_seconds,
            fallback_text=fallback_text,
        )

    async def synthesize_question(
        self,
        *,
        text: str,
        checkin_id: str,
        media_base_url: str,
        save_audio: Any | None = None,
    ) -> TtsResult:
        if save_audio is None:
            raise ValueError("save_audio callback is required for live TTS.")
        return await self.voice.synthesize_question(
            text=text,
            checkin_id=checkin_id,
            media_base_url=media_base_url,
            save_audio=save_audio,
        )

    async def answer_hotline(
        self,
        *,
        text: str,
        has_confirmed_record: bool,
        sender_id: str = "patient",
        session_id: str = "default",
    ) -> dict:
        answer = await self.bot.answer_hotline(
            text=text,
            has_confirmed_record=has_confirmed_record,
            sender_id=sender_id,
            session_id=session_id,
        )
        return {
            "answer_text": answer.answer_text,
            "source_scope": answer.source_scope,
            "needs_staff_review": answer.needs_staff_review,
            "risk_level": answer.risk_level,
            "reasons": answer.reasons,
        }

    async def cancel_ocr(self, vendor_job_id: str | None) -> None:
        if vendor_job_id:
            await self.reader.cancel_session(vendor_job_id)