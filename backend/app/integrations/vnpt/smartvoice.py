from __future__ import annotations

import asyncio
import uuid
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from app.core.config import Settings
from app.integrations.vnpt.auth import VNPTAuthService
from app.integrations.vnpt.client import (
    VNPTHttpClient,
    extract_object,
    extract_transcript,
    is_success_message,
)
from app.integrations.vnpt.types import SpeechResult, TtsResult


class SmartVoiceClient:
    TTS_PATH = "tts-service/v2/standard"
    STT_SYNC_PATH = "stt-service/v1/grpc/standard"
    STT_ASYNC_PATH = "stt-service/v1/grpc/async/standard"

    def __init__(self, settings: Settings, http: VNPTHttpClient, auth: VNPTAuthService) -> None:
        self.settings = settings
        self.http = http
        self.auth = auth

    async def transcribe_audio(
        self,
        *,
        file_bytes: bytes | None,
        filename: str | None,
        content_type: str | None,
        duration_seconds: int | None,
        fallback_text: str | None,
    ) -> SpeechResult:
        if not file_bytes:
            return SpeechResult(transcript=fallback_text or "")

        access_token = await self.auth.access_token("stt")
        client_session = self._new_client_session("stt")
        use_async = (
            duration_seconds is not None
            and duration_seconds > self.settings.vnpt_stt_async_duration_threshold_seconds
        )
        if use_async:
            transcript = await self._transcribe_async(
                file_bytes=file_bytes,
                filename=filename or "audio.m4a",
                content_type=content_type or "audio/m4a",
                access_token=access_token,
                client_session=client_session,
            )
        else:
            transcript = await self._transcribe_sync(
                file_bytes=file_bytes,
                filename=filename or "audio.m4a",
                content_type=content_type or "audio/m4a",
                access_token=access_token,
                client_session=client_session,
            )

        if not transcript.strip() and fallback_text:
            return SpeechResult(transcript=fallback_text)
        return SpeechResult(transcript=transcript)

    async def synthesize_question(
        self,
        *,
        text: str,
        checkin_id: str,
        media_base_url: str,
        save_audio: Callable[..., Awaitable[str]],
    ) -> TtsResult:
        access_token = await self.auth.access_token("tts")
        payload = await self.http.request_json(
            method="POST",
            base_url=self.settings.vnpt_idg_base_url,
            path=self.TTS_PATH,
            token_id=self.settings.vnpt_token_id_for("tts"),
            token_key=self.settings.vnpt_token_key_for("tts"),
            access_token=access_token,
            json_body={
                "text": text,
                "text_split": False,
                "model": self.settings.vnpt_tts_model,
                "speed": str(self.settings.vnpt_tts_speed),
                "region": self.settings.vnpt_tts_region,
                "audio_format": self.settings.vnpt_tts_format,
                "domain": "general",
            },
            include_mac=False,
        )
        obj = extract_object(payload)
        playlist = obj.get("playlist") or []
        audio_link = None
        if isinstance(playlist, list) and playlist:
            first = playlist[0]
            if isinstance(first, dict):
                audio_link = first.get("audio_link") or first.get("url")
        if not audio_link:
            raise ValueError("VNPT TTS v2 không trả audio_link trong playlist.")

        audio_bytes = await self.http.download_bytes(str(audio_link))
        ext = self._audio_extension(str(audio_link))
        storage_url = await save_audio(
            folder="tts",
            filename=f"{checkin_id}.{ext}",
            data=audio_bytes,
            content_type=self._audio_content_type(ext),
        )
        public_url = f"{str(media_base_url).rstrip('/')}{storage_url}"
        return TtsResult(
            audio_url=public_url,
            audio_cache_key=f"tts_{checkin_id}_v1",
        )

    async def _transcribe_sync(
        self,
        *,
        file_bytes: bytes,
        filename: str,
        content_type: str,
        access_token: str,
        client_session: str,
    ) -> str:
        payload = await self.http.upload_multipart(
            base_url=self.settings.vnpt_idg_base_url,
            path=self.STT_SYNC_PATH,
            token_id=self.settings.vnpt_token_id_for("stt"),
            token_key=self.settings.vnpt_token_key_for("stt"),
            access_token=access_token,
            field_name="audioFile",
            filename=filename,
            content=file_bytes,
            content_type=content_type,
            extra_fields={
                "clientSession": client_session,
                "enableAutomaticPunctuation": "true",
                "verbatimTranscripts": "false",
            },
            include_mac=False,
        )
        if not is_success_message(str(payload.get("message", ""))) and payload.get("message"):
            raise ValueError(str(payload.get("message")))
        transcript = extract_transcript(payload)
        if not transcript:
            raise ValueError("VNPT STT sync không trả transcript.")
        return transcript

    async def _transcribe_async(
        self,
        *,
        file_bytes: bytes,
        filename: str,
        content_type: str,
        access_token: str,
        client_session: str,
    ) -> str:
        payload = await self.http.upload_multipart(
            base_url=self.settings.vnpt_idg_base_url,
            path=self.STT_ASYNC_PATH,
            token_id=self.settings.vnpt_token_id_for("stt"),
            token_key=self.settings.vnpt_token_key_for("stt"),
            access_token=access_token,
            field_name="audioFile",
            filename=filename,
            content=file_bytes,
            content_type=content_type,
            extra_fields={
                "clientSession": client_session,
                "enableAutomaticPunctuation": "true",
                "verbatimTranscripts": "false",
            },
            include_mac=False,
            token_header_style="lowercase",
        )
        transcript = extract_transcript(payload)
        if transcript:
            return transcript
        status = self._status_from_payload(payload)
        if status in {"accepted", "processing", ""}:
            return await self._poll_async_result(client_session, access_token)
        if not is_success_message(str(payload.get("message", ""))) and payload.get("message"):
            raise ValueError(str(payload.get("message")))
        raise ValueError("VNPT STT async không trả transcript.")

    async def _poll_async_result(self, client_session: str, access_token: str) -> str:
        deadline = asyncio.get_event_loop().time() + self.settings.vnpt_stt_job_timeout_seconds
        while asyncio.get_event_loop().time() < deadline:
            payload = await self.http.upload_multipart(
                base_url=self.settings.vnpt_idg_base_url,
                path=self.STT_ASYNC_PATH,
                token_id=self.settings.vnpt_token_id_for("stt"),
                token_key=self.settings.vnpt_token_key_for("stt"),
                access_token=access_token,
                field_name="audioFile",
                content=None,
                extra_fields={"clientSession": client_session},
                include_mac=False,
                token_header_style="lowercase",
            )
            transcript = extract_transcript(payload)
            if transcript:
                return transcript
            status = self._status_from_payload(payload)
            if status in {"failed", "error", "cancelled"}:
                obj = extract_object(payload)
                raise ValueError(obj.get("message") or "VNPT STT async thất bại.")
            if status == "ok":
                raise ValueError("VNPT STT async hoàn tất nhưng không trả transcript.")
            if not is_success_message(str(payload.get("message", ""))) and payload.get("message"):
                state = str(payload.get("message"))
                if "processing" not in state.lower() and "accepted" not in state.lower():
                    raise ValueError(state)
            await asyncio.sleep(self.settings.vnpt_stt_poll_interval_seconds)
        raise TimeoutError("VNPT STT async timeout.")

    def _status_from_payload(self, payload: dict[str, Any]) -> str:
        obj = extract_object(payload)
        return str(obj.get("status") or obj.get("Status") or obj.get("state") or payload.get("status") or "").lower()

    def _new_client_session(self, prefix: str) -> str:
        base = self.settings.vnpt_client_session.strip() or "carevoice"
        return f"{base}-{prefix}-{uuid.uuid4().hex}"

    def _audio_extension(self, audio_link: str) -> str:
        suffix = Path(urlparse(audio_link).path).suffix.lower().lstrip(".")
        if suffix in {"mp3", "wav", "m4a"}:
            return suffix
        return self.settings.vnpt_tts_format or "mp3"

    def _audio_content_type(self, ext: str) -> str:
        return {
            "mp3": "audio/mpeg",
            "wav": "audio/wav",
            "m4a": "audio/m4a",
        }.get(ext, "application/octet-stream")
