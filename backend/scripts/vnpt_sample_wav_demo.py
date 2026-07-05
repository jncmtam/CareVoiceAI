#!/usr/bin/env python3
"""Demo STT → SmartBot (+ TTS) với file WAV mẫu.

Mặc định dùng `test/stt/STT.sample.wav` trong repo. Cần `backend/.env` với
`VENDOR_MOCK_MODE=false` và credential VNPT để gọi API live.

Ví dụ:
  python scripts/vnpt_sample_wav_demo.py
  python scripts/vnpt_sample_wav_demo.py --wav /path/to/audio.wav
  python scripts/vnpt_sample_wav_demo.py --mock
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import wave
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from dotenv import load_dotenv

load_dotenv(ROOT / ".env")

DEFAULT_WAV = ROOT / "test" / "stt" / "STT.sample.wav"
OUTPUT_DIR = ROOT / "test" / "tts" / "generated"


def _wav_duration_seconds(path: Path) -> int | None:
    try:
        with wave.open(str(path), "rb") as handle:
            frames = handle.getnframes()
            rate = handle.getframerate()
            if rate <= 0:
                return None
            return max(1, int(round(frames / rate)))
    except wave.Error:
        return None


def _print_section(title: str) -> None:
    print()
    print(f"=== {title} ===")


def _print_json(label: str, payload: object) -> None:
    print(f"{label}:")
    print(json.dumps(payload, ensure_ascii=False, indent=2))


async def run_demo(
    *,
    wav_path: Path,
    use_mock: bool,
    skip_tts: bool,
    skip_smartbot: bool,
    smartbot_text: str | None,
    has_confirmed_record: bool,
) -> int:
    if use_mock:
        os.environ["VENDOR_MOCK_MODE"] = "true"
    else:
        os.environ["VENDOR_MOCK_MODE"] = "false"

    from app.core.config import get_settings
    from app.integrations.vnpt import get_vnpt_gateway

    settings = get_settings()
    gateway = get_vnpt_gateway(settings)
    results: list[tuple[str, str]] = []
    transcript = smartbot_text

    print("CareVoice VNPT demo (STT / TTS / SmartBot)")
    print(f"WAV file      : {wav_path}")
    print(f"Mock mode     : {settings.vendor_mock_mode}")
    print(f"IDG base      : {settings.vnpt_idg_base_url}")
    print(f"SmartBot base : {settings.vnpt_smartbot_base_url}")
    print(f"Bot ID        : {settings.vnpt_smartbot_bot_id or '(chưa cấu hình)'}")

    if not wav_path.exists():
        print(f"\n❌ Không tìm thấy file WAV: {wav_path}")
        return 1

    audio_bytes = wav_path.read_bytes()
    duration = _wav_duration_seconds(wav_path)
    print(f"Audio size    : {len(audio_bytes):,} bytes")
    print(f"Duration est. : {duration or '?'} giây")

    _print_section("1) STT — nhận dạng giọng nói")
    try:
        speech = await gateway.transcribe_audio(
            file_url=None,
            file_bytes=audio_bytes,
            filename=wav_path.name,
            content_type="audio/wav",
            duration_seconds=duration,
            fallback_text=None,
        )
        transcript = (speech.transcript or "").strip()
        if not transcript:
            raise ValueError("STT trả transcript rỗng.")
        print(f"✅ Transcript ({len(transcript)} ký tự):")
        print(f"   {transcript}")
        results.append(("STT", "OK"))
    except Exception as exc:  # noqa: BLE001
        print(f"❌ STT FAIL: {exc}")
        results.append(("STT", f"FAIL: {exc}"))

    if not skip_tts:
        _print_section("2) TTS — tổng hợp giọng nói")
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        tts_text = transcript or "Bác hôm nay thấy trong người thế nào?"
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

        async def _save_audio(folder: str, filename: str, data: bytes, content_type: str) -> str:
            target = OUTPUT_DIR / filename
            target.write_bytes(data)
            print(f"   Saved: {target} ({len(data):,} bytes, {content_type})")
            return f"/media/{folder}/{filename}"

        try:
            tts = await gateway.synthesize_question(
                text=tts_text[:500],
                checkin_id=f"demo-{stamp}",
                media_base_url=settings.media_base_url,
                save_audio=_save_audio,
            )
            print("✅ TTS OK")
            print(f"   audio_url: {tts.audio_url}")
            print(f"   cache_key: {tts.audio_cache_key}")
            results.append(("TTS", "OK"))
        except Exception as exc:  # noqa: BLE001
            print(f"❌ TTS FAIL: {exc}")
            results.append(("TTS", f"FAIL: {exc}"))

    if not skip_smartbot:
        _print_section("3) SmartBot — trả lời / phân loại hotline")
        question = (smartbot_text or transcript or "").strip()
        if not question:
            print("⏭️  SKIP SmartBot: không có transcript hoặc --smartbot-text.")
            results.append(("SmartBot", "SKIP: no text"))
        elif not settings.vendor_mock_mode and not settings.vnpt_smartbot_bot_id:
            print("⏭️  SKIP SmartBot: VNPT_SMARTBOT_BOT_ID chưa cấu hình.")
            results.append(("SmartBot", "SKIP: no bot id"))
        else:
            try:
                answer = await gateway.answer_hotline(
                    text=question,
                    has_confirmed_record=has_confirmed_record,
                    sender_id="vnpt-demo-patient",
                    session_id="vnpt-demo-session",
                )
                print("✅ SmartBot OK")
                _print_json("   Response", answer)
                results.append(("SmartBot", "OK"))
            except Exception as exc:  # noqa: BLE001
                print(f"❌ SmartBot FAIL: {exc}")
                results.append(("SmartBot", f"FAIL: {exc}"))

    if transcript and not skip_smartbot and smartbot_text is None:
        _print_section("4) Pipeline STT → SmartBot")
        print("Luồng: file WAV → STT transcript → SmartBot answer")
        print(f"Input audio : {wav_path.name}")
        print(f"Transcript  : {transcript}")
        if any(item[0] == "SmartBot" and item[1] == "OK" for item in results):
            print("Pipeline    : ✅ hoàn tất")

    _print_section("Tổng kết")
    passed = failed = skipped = 0
    for name, status in results:
        if status == "OK":
            mark, passed = "✅", passed + 1
        elif status.startswith("SKIP"):
            mark, skipped = "⏭️ ", skipped + 1
        else:
            mark, failed = "❌", failed + 1
        print(f"{mark} {name}: {status}")
    print(f"\nKết quả: {passed} OK, {failed} FAIL, {skipped} SKIP")
    return 0 if failed == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Demo VNPT STT/TTS/SmartBot với file WAV.")
    parser.add_argument(
        "--wav",
        type=Path,
        default=DEFAULT_WAV,
        help=f"Đường dẫn file WAV (mặc định: {DEFAULT_WAV})",
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Dùng mock gateway thay vì gọi VNPT live.",
    )
    parser.add_argument("--skip-tts", action="store_true", help="Bỏ qua bước TTS.")
    parser.add_argument("--skip-smartbot", action="store_true", help="Bỏ qua bước SmartBot.")
    parser.add_argument(
        "--smartbot-text",
        default=None,
        help="Gửi text cố định cho SmartBot thay vì dùng transcript STT.",
    )
    parser.add_argument(
        "--no-confirmed-record",
        action="store_true",
        help="SmartBot giả định chưa có hồ sơ thuốc xác nhận.",
    )
    args = parser.parse_args()
    return asyncio.run(
        run_demo(
            wav_path=args.wav.expanduser().resolve(),
            use_mock=args.mock,
            skip_tts=args.skip_tts,
            skip_smartbot=args.skip_smartbot,
            smartbot_text=args.smartbot_text,
            has_confirmed_record=not args.no_confirmed_record,
        )
    )


if __name__ == "__main__":
    raise SystemExit(main())