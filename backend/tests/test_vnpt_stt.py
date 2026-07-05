from unittest.mock import AsyncMock

import pytest

from app.core.config import Settings
from app.integrations.vnpt.auth import VNPTAuthService
from app.integrations.vnpt.client import VNPTHttpClient, extract_transcript
from app.integrations.vnpt.smartvoice import SmartVoiceClient


def test_extract_transcript_from_object_text() -> None:
    payload = {"message": "IDG-00000000", "object": {"text": "Hôm nay tôi thấy bình thường."}}
    assert extract_transcript(payload) == "Hôm nay tôi thấy bình thường."


def test_extract_transcript_from_sentences() -> None:
    payload = {
        "object": {
            "sentences": [
                {"text": "Không đau ngực"},
                {"text": "không khó thở"},
            ]
        }
    }
    assert extract_transcript(payload) == "Không đau ngực không khó thở"


def test_extract_transcript_from_vnpt_results() -> None:
    payload = {
        "message": "IDG-00000000",
        "object": {
            "results": [
                {
                    "alternatives": [
                        {
                            "transcript": "Tôi bị chóng mặt nhẹ.",
                            "confidence": -1.6,
                        }
                    ],
                    "channelTag": 1,
                }
            ],
            "status": "OK",
        },
    }

    assert extract_transcript(payload) == "Tôi bị chóng mặt nhẹ."


@pytest.mark.asyncio
async def test_transcribe_sync_uses_standard_endpoint() -> None:
    settings = Settings(vnpt_access_token="test-token")
    http = VNPTHttpClient(settings)
    auth = VNPTAuthService(settings, http)
    client = SmartVoiceClient(settings, http, auth)
    client.http.upload_multipart = AsyncMock(  # type: ignore[method-assign]
        return_value={"message": "IDG-00000000", "object": {"text": "Có mệt nhẹ."}}
    )

    result = await client.transcribe_audio(
        file_bytes=b"audio",
        filename="voice.m4a",
        content_type="audio/m4a",
        duration_seconds=10,
        fallback_text=None,
    )

    assert result.transcript == "Có mệt nhẹ."
    client.http.upload_multipart.assert_awaited_once()
    assert client.http.upload_multipart.await_args.kwargs["path"] == "stt-service/v1/grpc/standard"


@pytest.mark.asyncio
async def test_transcribe_async_uses_async_endpoint() -> None:
    settings = Settings(vnpt_access_token="test-token")
    http = VNPTHttpClient(settings)
    auth = VNPTAuthService(settings, http)
    client = SmartVoiceClient(settings, http, auth)
    client.http.upload_multipart = AsyncMock(  # type: ignore[method-assign]
        return_value={"message": "IDG-00000000", "object": {"text": "Tôi bị chóng mặt."}}
    )

    result = await client.transcribe_audio(
        file_bytes=b"audio",
        filename="voice.m4a",
        content_type="audio/m4a",
        duration_seconds=45,
        fallback_text=None,
    )

    assert result.transcript == "Tôi bị chóng mặt."
    assert client.http.upload_multipart.await_args.kwargs["path"] == "stt-service/v1/grpc/async/standard"
    assert client.http.upload_multipart.await_args.kwargs["token_header_style"] == "lowercase"


@pytest.mark.asyncio
async def test_transcribe_async_polls_same_endpoint_with_client_session() -> None:
    settings = Settings(vnpt_access_token="test-token", vnpt_stt_poll_interval_seconds=0.001)
    http = VNPTHttpClient(settings)
    auth = VNPTAuthService(settings, http)
    client = SmartVoiceClient(settings, http, auth)
    client.http.upload_multipart = AsyncMock(  # type: ignore[method-assign]
        side_effect=[
            {"message": "IDG-00000000", "object": {"message": "Processing", "status": "ACCEPTED"}},
            {
                "message": "IDG-00000000",
                "object": {
                    "results": [{"alternatives": [{"transcript": "Đã có kết quả."}], "channelTag": 1}],
                    "status": "OK",
                },
            },
        ]
    )

    result = await client.transcribe_audio(
        file_bytes=b"audio",
        filename="voice.m4a",
        content_type="audio/m4a",
        duration_seconds=45,
        fallback_text=None,
    )

    assert result.transcript == "Đã có kết quả."
    first_call, second_call = client.http.upload_multipart.await_args_list
    assert first_call.kwargs["path"] == "stt-service/v1/grpc/async/standard"
    assert second_call.kwargs["path"] == "stt-service/v1/grpc/async/standard"
    assert second_call.kwargs["content"] is None
    assert first_call.kwargs["extra_fields"]["clientSession"] == second_call.kwargs["extra_fields"]["clientSession"]


@pytest.mark.asyncio
async def test_transcribe_falls_back_when_no_audio() -> None:
    settings = Settings(vnpt_access_token="test-token")
    client = SmartVoiceClient(settings, VNPTHttpClient(settings), VNPTAuthService(settings, VNPTHttpClient(settings)))

    result = await client.transcribe_audio(
        file_bytes=None,
        filename=None,
        content_type=None,
        duration_seconds=None,
        fallback_text="Không có triệu chứng bất thường hôm nay.",
    )

    assert result.transcript == "Không có triệu chứng bất thường hôm nay."
