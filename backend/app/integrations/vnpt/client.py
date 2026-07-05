from __future__ import annotations

import asyncio
import json
from typing import Any

import httpx
import structlog

from app.core.config import Settings
from app.core.errors import APIError

logger = structlog.get_logger(__name__)


class VNPTHttpClient:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._client: httpx.AsyncClient | None = None

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=self.settings.request_timeout_seconds)
        return self._client

    def build_headers(
        self,
        *,
        token_id: str,
        token_key: str,
        access_token: str,
        include_mac: bool = True,
        content_type: str | None = "application/json",
        token_header_style: str = "capital",
    ) -> dict[str, str]:
        headers: dict[str, str] = {"Accept": "application/json"}
        if content_type:
            headers["Content-Type"] = content_type
        if access_token:
            token = access_token if access_token.startswith("Bearer ") else f"Bearer {access_token}"
            headers["Authorization"] = token
        if token_id:
            id_key = "token-id" if token_header_style == "lowercase" else "Token-id"
            headers[id_key] = token_id
        if token_key:
            key_key = "token-key" if token_header_style == "lowercase" else "Token-key"
            headers[key_key] = token_key
        if include_mac and self.settings.vnpt_mac_address:
            headers["mac-address"] = self.settings.vnpt_mac_address
        return headers

    async def request_json(
        self,
        *,
        method: str,
        base_url: str,
        path: str,
        token_id: str,
        token_key: str,
        access_token: str,
        json_body: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
        retries: int = 2,
        include_mac: bool = True,
        token_header_style: str = "capital",
    ) -> dict[str, Any]:
        url = f"{base_url.rstrip('/')}/{path.lstrip('/')}"
        last_error: Exception | None = None
        for attempt in range(retries + 1):
            try:
                response = await self._get_client().request(
                    method,
                    url,
                    headers=self.build_headers(
                        token_id=token_id,
                        token_key=token_key,
                        access_token=access_token,
                        include_mac=include_mac,
                        token_header_style=token_header_style,
                    ),
                    json=json_body,
                    params=params,
                )
                if response.status_code in {429, 503} and attempt < retries:
                    await asyncio.sleep(0.5 * (attempt + 1))
                    continue
                if response.status_code >= 500:
                    raise APIError("vendor_unavailable", "Dịch vụ VNPT tạm thời không khả dụng.", 503)
                if response.status_code >= 400:
                    logger.warning(
                        "vnpt_request_failed",
                        method=method,
                        path=path,
                        status=response.status_code,
                    )
                    raise APIError(
                        "vendor_unavailable",
                        f"VNPT trả lỗi HTTP {response.status_code}.",
                        503,
                        {"body": response.text[:500]},
                    )
                logger.info("vnpt_request_ok", method=method, path=path, status=response.status_code)
                data = response.json()
                if not isinstance(data, dict):
                    return {"object": data}
                return data
            except APIError:
                raise
            except httpx.TimeoutException as exc:
                last_error = exc
                if attempt < retries:
                    await asyncio.sleep(0.5 * (attempt + 1))
                    continue
                raise APIError(
                    "job_timeout",
                    "Hệ thống xử lý quá lâu. Vui lòng thử lại sau.",
                    504,
                ) from exc
            except httpx.HTTPError as exc:
                last_error = exc
                if attempt < retries:
                    await asyncio.sleep(0.5 * (attempt + 1))
                    continue
                raise APIError("vendor_unavailable", "Không thể kết nối dịch vụ VNPT.", 503) from exc
        raise APIError("vendor_unavailable", "Không thể kết nối dịch vụ VNPT.", 503) from last_error

    async def request_sse_json(
        self,
        *,
        method: str,
        base_url: str,
        path: str,
        token_id: str,
        token_key: str,
        access_token: str,
        json_body: dict[str, Any] | None = None,
        retries: int = 2,
        include_mac: bool = True,
        token_header_style: str = "capital",
    ) -> dict[str, Any]:
        url = f"{base_url.rstrip('/')}/{path.lstrip('/')}"
        last_error: Exception | None = None
        for attempt in range(retries + 1):
            try:
                response = await self._get_client().request(
                    method,
                    url,
                    headers={
                        **self.build_headers(
                            token_id=token_id,
                            token_key=token_key,
                            access_token=access_token,
                            include_mac=include_mac,
                            content_type="application/json",
                            token_header_style=token_header_style,
                        ),
                        "Accept": "text/event-stream",
                        "Cache-Control": "no-cache",
                        "Connection": "keep-alive",
                    },
                    json=json_body,
                )
                if response.status_code in {429, 503} and attempt < retries:
                    await asyncio.sleep(0.5 * (attempt + 1))
                    continue
                if response.status_code >= 500:
                    raise APIError("vendor_unavailable", "Dịch vụ VNPT tạm thời không khả dụng.", 503)
                if response.status_code >= 400:
                    raise APIError(
                        "vendor_unavailable",
                        f"VNPT trả lỗi HTTP {response.status_code}.",
                        503,
                        {"body": response.text[:500]},
                    )
                events = parse_sse_json_events(response.text)
                merged = merge_conversation_events(events)
                if not merged:
                    return {"object": {}}
                return merged
            except APIError:
                raise
            except httpx.TimeoutException as exc:
                last_error = exc
                if attempt < retries:
                    await asyncio.sleep(0.5 * (attempt + 1))
                    continue
                raise APIError(
                    "job_timeout",
                    "Hệ thống xử lý quá lâu. Vui lòng thử lại sau.",
                    504,
                ) from exc
            except httpx.HTTPError as exc:
                last_error = exc
                if attempt < retries:
                    await asyncio.sleep(0.5 * (attempt + 1))
                    continue
                raise APIError("vendor_unavailable", "Không thể kết nối dịch vụ VNPT.", 503) from exc
        raise APIError("vendor_unavailable", "Không thể kết nối dịch vụ VNPT.", 503) from last_error

    async def upload_multipart(
        self,
        *,
        base_url: str,
        path: str,
        token_id: str,
        token_key: str,
        access_token: str,
        field_name: str | None,
        filename: str | None = None,
        content: bytes | None = None,
        content_type: str | None = None,
        extra_fields: dict[str, str] | None = None,
        include_mac: bool = True,
        token_header_style: str = "capital",
    ) -> dict[str, Any]:
        url = f"{base_url.rstrip('/')}/{path.lstrip('/')}"
        files = None
        if field_name and content is not None:
            files = {field_name: (filename or "upload.bin", content, content_type or "application/octet-stream")}
        elif field_name:
            files = {field_name: ("", b"", "application/octet-stream")}
        data = extra_fields or {}
        try:
            response = await self._get_client().post(
                url,
                headers=self.build_headers(
                    token_id=token_id,
                    token_key=token_key,
                    access_token=access_token,
                    content_type=None,
                    include_mac=include_mac,
                    token_header_style=token_header_style,
                ),
                files=files,
                data=data,
            )
        except httpx.TimeoutException as exc:
            raise APIError("job_timeout", "Hệ thống xử lý quá lâu. Vui lòng thử lại sau.", 504) from exc
        except httpx.HTTPError as exc:
            raise APIError("vendor_unavailable", "Không thể upload file lên VNPT.", 503) from exc
        if response.status_code >= 400:
            raise APIError(
                "vendor_unavailable",
                f"VNPT upload lỗi HTTP {response.status_code}.",
                503,
                {"body": response.text[:500]},
            )
        data = response.json()
        return data if isinstance(data, dict) else {"object": data}

    async def download_bytes(self, url: str) -> bytes:
        try:
            response = await self._get_client().get(url)
            response.raise_for_status()
            return response.content
        except httpx.HTTPError as exc:
            raise APIError("vendor_unavailable", "Không thể tải file từ VNPT.", 503) from exc


def parse_sse_json_events(raw: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped.startswith("data:"):
            continue
        body = stripped[5:].strip()
        if not body:
            continue
        parsed = json.loads(body)
        if isinstance(parsed, dict):
            events.append(parsed)
    return events


def merge_conversation_events(events: list[dict[str, Any]]) -> dict[str, Any]:
    if not events:
        return {}
    merged_cards: list[dict[str, Any]] = []
    for event in events:
        sb = extract_object(event).get("sb")
        if not isinstance(sb, dict):
            continue
        cards = sb.get("card_data")
        if isinstance(cards, list):
            merged_cards.extend(card for card in cards if isinstance(card, dict))

    final = events[-1]
    obj = extract_object(final)
    sb = obj.get("sb") if isinstance(obj.get("sb"), dict) else {}
    if merged_cards:
        sb = {**sb, "card_data": merged_cards}
    return {**final, "object": {**obj, "sb": sb}}


def extract_object(payload: dict[str, Any]) -> dict[str, Any]:
    obj = payload.get("object")
    if isinstance(obj, dict):
        return obj
    data = payload.get("data")
    if isinstance(data, dict):
        return data
    return payload


def is_success_message(message: str | None) -> bool:
    if not message:
        return True
    return message in {"IDG-00000000", "success", "SUCCESS", "OK"}


def extract_transcript(payload: dict[str, Any]) -> str:
    obj = extract_object(payload)
    for source in (obj, payload):
        transcript = _extract_transcript_from_results(source)
        if transcript:
            return transcript
        for key in ("text", "transcript", "content", "result"):
            value = source.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        sentences = source.get("sentences") or source.get("sentence")
        if isinstance(sentences, list):
            parts: list[str] = []
            for item in sentences:
                if isinstance(item, dict):
                    text = item.get("text") or item.get("content") or item.get("transcript")
                    if text:
                        parts.append(str(text).strip())
                elif isinstance(item, str) and item.strip():
                    parts.append(item.strip())
            if parts:
                return " ".join(parts)
        hypotheses = source.get("hypotheses")
        if isinstance(hypotheses, list) and hypotheses:
            first = hypotheses[0]
            if isinstance(first, dict):
                text = first.get("text") or first.get("transcript")
                if isinstance(text, str) and text.strip():
                    return text.strip()
    return ""


def _extract_transcript_from_results(source: dict[str, Any]) -> str:
    results = source.get("results") or source.get("Results") or source.get("result") or source.get("Result")
    if not isinstance(results, list):
        return ""
    parts: list[str] = []
    for item in results:
        if not isinstance(item, dict):
            continue
        direct = item.get("transcript") or item.get("text")
        if isinstance(direct, str) and direct.strip():
            parts.append(direct.strip())
            continue
        alternatives = item.get("alternatives") or item.get("Alternatives")
        if not isinstance(alternatives, list):
            continue
        for alternative in alternatives[:1]:
            if not isinstance(alternative, dict):
                continue
            text = alternative.get("transcript") or alternative.get("text")
            if isinstance(text, str) and text.strip():
                parts.append(text.strip())
    return " ".join(parts)
