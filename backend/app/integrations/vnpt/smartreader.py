from __future__ import annotations

import asyncio
import uuid
from typing import Any

from app.core.config import Settings
from app.integrations.vnpt.auth import VNPTAuthService
from app.integrations.vnpt.client import VNPTHttpClient, extract_object, is_success_message
from app.integrations.vnpt.parsers.prescription import parse_ocr_payload
from app.integrations.vnpt.types import OcrResult


class SmartReaderClient:
    SCAN_TABLE_PATH = "rpa-service/aidigdoc/v1/ocr/scan-table"
    SCAN_TABLE_RESULT_PATH = "rpa-service/aidigdoc/v1/ocr/scan-table/result"

    def __init__(self, settings: Settings, http: VNPTHttpClient, auth: VNPTAuthService) -> None:
        self.settings = settings
        self.http = http
        self.auth = auth

    async def scan_medical_document(
        self,
        *,
        file_bytes: bytes,
        filename: str,
        content_type: str,
        mode: str,
    ) -> tuple[OcrResult, str | None]:
        access_token = await self.auth.access_token("smartreader")
        client_session = self._new_client_session("ocr")
        upload = await self.http.upload_multipart(
            base_url=self.settings.vnpt_idg_base_url,
            path="file-service/v1/addFile",
            token_id=self.settings.vnpt_token_id_for("smartreader"),
            token_key=self.settings.vnpt_token_key_for("smartreader"),
            access_token=access_token,
            field_name="file",
            filename=filename,
            content=file_bytes,
            content_type=content_type,
        )
        uploaded = extract_object(upload)
        file_hash = uploaded.get("hash") or uploaded.get("file_hash") or uploaded.get("file_id")
        if not file_hash:
            raise ValueError("VNPT addFile không trả file_hash.")

        file_type = "pdf" if filename.lower().endswith(".pdf") or content_type == "application/pdf" else "images"
        body = {
            "file_hash": file_hash,
            "file_type": file_type,
            "token": self.settings.vnpt_client_token,
            "client_session": client_session,
            "details": mode != "basic",
        }
        started = await self.http.request_json(
            method="POST",
            base_url=self.settings.vnpt_idg_base_url,
            path=self.SCAN_TABLE_PATH,
            token_id=self.settings.vnpt_token_id_for("smartreader"),
            token_key=self.settings.vnpt_token_key_for("smartreader"),
            access_token=access_token,
            json_body=body,
        )
        if not is_success_message(str(started.get("message", ""))):
            raise ValueError(started.get("message") or "scan-table thất bại.")

        started_obj = extract_object(started)
        session_id = started_obj.get("session_id") or started_obj.get("request_id") or started_obj.get("id")
        if session_id:
            structured, raw_text = await self._poll_table_result(str(session_id), access_token)
        else:
            structured = started_obj
            raw_text = (
                structured.get("text")
                or structured.get("raw_text")
                or structured.get("content")
                or ""
            )
        return parse_ocr_payload(raw_text=str(raw_text), structured=structured), (
            str(session_id or client_session)
        )

    async def cancel_session(self, vendor_job_id: str) -> None:
        access_token = await self.auth.access_token("smartreader")
        await self.http.request_json(
            method="POST",
            base_url=self.settings.vnpt_idg_base_url,
            path=f"{self.SCAN_TABLE_RESULT_PATH}/{vendor_job_id}/cancel",
            token_id=self.settings.vnpt_token_id_for("smartreader"),
            token_key=self.settings.vnpt_token_key_for("smartreader"),
            access_token=access_token,
            json_body={"session_id": vendor_job_id},
        )

    async def _poll_table_result(self, session_id: str, access_token: str) -> tuple[dict[str, Any], str]:
        deadline = asyncio.get_event_loop().time() + self.settings.vnpt_ocr_job_timeout_seconds
        while asyncio.get_event_loop().time() < deadline:
            payload = await self.http.request_json(
                method="GET",
                base_url=self.settings.vnpt_idg_base_url,
                path=f"{self.SCAN_TABLE_RESULT_PATH}/{session_id}",
                token_id=self.settings.vnpt_token_id_for("smartreader"),
                token_key=self.settings.vnpt_token_key_for("smartreader"),
                access_token=access_token,
            )
            if not is_success_message(str(payload.get("message", ""))) and payload.get("message"):
                state = str(payload.get("message"))
                if "processing" not in state.lower():
                    raise ValueError(state)
            obj = extract_object(payload)
            status = str(obj.get("status") or obj.get("state") or "").lower()
            if status in {"done", "completed", "success", "needs_review"} or obj.get("text") or obj.get("tables"):
                raw_text = obj.get("text") or obj.get("raw_text") or obj.get("content") or ""
                return obj, str(raw_text)
            if status in {"failed", "error", "cancelled"}:
                raise ValueError(obj.get("message") or "OCR scan-table thất bại.")
            await asyncio.sleep(self.settings.vnpt_ocr_poll_interval_seconds)
        raise TimeoutError("OCR scan-table timeout.")

    def _new_client_session(self, prefix: str) -> str:
        base = self.settings.vnpt_client_session.strip() or "carevoice"
        return f"{base}-{prefix}-{uuid.uuid4().hex}"
