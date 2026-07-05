import os
from pathlib import Path

TEST_DB = Path("test_storage_limits.db")
TEST_DB.unlink(missing_ok=True)
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_storage_limits.db"
os.environ["SEED_DEMO_DATA"] = "true"
os.environ["AUTO_CREATE_TABLES"] = "true"
os.environ["VENDOR_MOCK_MODE"] = "true"

from fastapi.testclient import TestClient  # noqa: E402

from app.core.config import get_settings  # noqa: E402
from app.main import app  # noqa: E402

get_settings.cache_clear()


def _apply_tight_limits(monkeypatch) -> None:
    monkeypatch.setenv("MAX_DOCUMENT_UPLOAD_BYTES", "128")
    monkeypatch.setenv("MAX_AUDIO_UPLOAD_BYTES", "256")
    get_settings.cache_clear()


def auth_headers(client: TestClient, role: str = "staff") -> dict[str, str]:
    if role == "staff":
        response = client.post(
            "/api/v1/auth/staff/login",
            json={"login": "nurse", "password": "nurse", "device_id": "dev-staff"},
        )
    else:
        response = client.post(
            "/api/v1/auth/patient/login",
            json={
                "login": "patient",
                "password": "patient",
                "device_id": "dev-patient",
            },
        )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_document_upload_rejects_oversized_pdf(monkeypatch) -> None:
    _apply_tight_limits(monkeypatch)
    with TestClient(app) as client:
        headers = auth_headers(client, "staff")
        response = client.post(
            "/api/v1/patients/pat_001/documents",
            headers=headers,
            data={
                "document_type": "prescription",
                "ocr_mode": "auto",
                "client_request_id": "test-doc-too-large",
            },
            files={"file": ("prescription.pdf", b"x" * 256, "application/pdf")},
        )
        assert response.status_code == 413, response.text
        body = response.json()
        assert body["error"]["code"] == "file_too_large"


def test_document_upload_rejects_unsupported_media_type(monkeypatch) -> None:
    _apply_tight_limits(monkeypatch)
    with TestClient(app) as client:
        headers = auth_headers(client, "staff")
        response = client.post(
            "/api/v1/patients/pat_001/documents",
            headers=headers,
            data={
                "document_type": "prescription",
                "ocr_mode": "auto",
                "client_request_id": "test-doc-unsupported",
            },
            files={"file": ("notes.txt", b"plain text", "text/plain")},
        )
        assert response.status_code == 415, response.text
        body = response.json()
        assert body["error"]["code"] == "unsupported_media_type"


def test_checkin_audio_upload_rejects_oversized_file(monkeypatch) -> None:
    _apply_tight_limits(monkeypatch)
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        today = client.get("/api/v1/me/checkins/today", headers=headers)
        assert today.status_code == 200, today.text
        checkin_id = today.json()["checkin"]["id"]
        response = client.post(
            f"/api/v1/checkins/{checkin_id}/responses",
            headers=headers,
            data={
                "client_recorded_at": "2026-07-02T05:00:00Z",
                "client_request_id": "test-checkin-too-large",
            },
            files={"audio_file": ("voice.m4a", b"x" * 512, "audio/m4a")},
        )
        assert response.status_code == 413, response.text
        body = response.json()
        assert body["error"]["code"] == "file_too_large"