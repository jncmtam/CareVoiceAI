#!/usr/bin/env python3
"""Quick live connectivity check for VNPT credentials in backend/.env."""

from __future__ import annotations

import asyncio
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv

load_dotenv(ROOT / ".env")

os.environ.setdefault("VENDOR_MOCK_MODE", "false")

from app.core.config import get_settings
from app.integrations.vnpt import get_vnpt_gateway


async def main() -> int:
    settings = get_settings()
    gateway = get_vnpt_gateway(settings)
    results: list[tuple[str, str]] = []

    print("=== VNPT live check ===")
    print(f"VENDOR_MOCK_MODE={settings.vendor_mock_mode}")
    print(f"IDG base: {settings.vnpt_idg_base_url}")
    print()

    async def _save_audio(_filename: str, data: bytes) -> str:
        return f"{settings.media_base_url}/media/tts/{_filename}"

    try:
        tts = await gateway.synthesize_question(
            text="Bác hôm nay thấy trong người thế nào?",
            checkin_id="live-check-tts",
            media_base_url=settings.media_base_url,
            save_audio=_save_audio,
        )
        ok = bool(tts.audio_url or tts.status)
        results.append(("TTS", "OK" if ok else f"unexpected: {tts}"))
    except Exception as exc:  # noqa: BLE001
        results.append(("TTS", f"FAIL: {exc}"))

    try:
        stt = await gateway.transcribe_audio(
            file_url=None,
            file_bytes=None,
            filename=None,
            content_type=None,
            duration_seconds=5,
            fallback_text="Không có triệu chứng bất thường hôm nay.",
        )
        results.append(("STT fallback", "OK" if stt.transcript else "empty transcript"))
    except Exception as exc:  # noqa: BLE001
        results.append(("STT fallback", f"FAIL: {exc}"))

    try:
        ocr, vendor_job_id = await gateway.scan_medical_document(
            file_url=None,
            file_bytes=b"Metformin 500mg\nUong 2 lan moi ngay sau an",
            filename="prescription.txt",
            content_type="text/plain",
            mode="auto",
            document_type="prescription",
        )
        results.append(
            (
                "OCR",
                f"OK status={ocr.status} meds={len(ocr.draft_medications or [])} vendor_job={vendor_job_id or '-'}",
            )
        )
    except Exception as exc:  # noqa: BLE001
        results.append(("OCR", f"FAIL: {exc}"))

    if settings.vnpt_smartbot_bot_id:
        try:
            bot = await gateway.answer_hotline(
                text="Tôi quên uống thuốc sáng nay thì làm sao?",
                has_confirmed_record=True,
            )
            answer = bot.get("answer") or bot.get("message") or str(bot)[:120]
            results.append(("SmartBot", f"OK: {answer}"))
        except Exception as exc:  # noqa: BLE001
            results.append(("SmartBot", f"FAIL: {exc}"))
    else:
        results.append(("SmartBot", "SKIP: VNPT_SMARTBOT_BOT_ID chưa cấu hình"))

    passed = 0
    failed = 0
    for name, status in results:
        mark = "✅" if status.startswith("OK") or status.startswith("SKIP") else "❌"
        print(f"{mark} {name}: {status}")
        if status.startswith("OK"):
            passed += 1
        elif status.startswith("SKIP"):
            pass
        else:
            failed += 1

    print()
    print(f"Kết quả: {passed} OK, {failed} FAIL, {len(results) - passed - failed} SKIP")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))