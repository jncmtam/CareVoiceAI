import os
from pathlib import Path

TEST_DB = Path("test_carevoice.db")
TEST_DB.unlink(missing_ok=True)
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_carevoice.db"
os.environ["SEED_DEMO_DATA"] = "true"
os.environ["AUTO_CREATE_TABLES"] = "true"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402


def auth_headers(client: TestClient, role: str = "staff") -> dict[str, str]:
    if role == "staff":
        response = client.post(
            "/api/v1/auth/staff/login",
            json={"login": "nurse01@hospital.vn", "password": "secret", "device_id": "dev-staff"},
        )
    else:
        response = client.post(
            "/api/v1/auth/patient/login_code",
            json={
                "patient_code": "BN-2026-0001",
                "phone_last4": "4567",
                "device_id": "dev-patient",
            },
        )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_staff_dashboard_contract() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "staff")
        response = client.get("/api/v1/staff/dashboard/overview", headers=headers)
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["total_active_patients"] >= 1
        assert "updated_at" in body
        assert body["updated_at"].endswith("Z")


def test_patient_checkin_submit_and_poll() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        today = client.get("/api/v1/me/checkins/today", headers=headers)
        assert today.status_code == 200, today.text
        checkin_id = today.json()["checkin"]["id"]
        submitted = client.post(
            f"/api/v1/checkins/{checkin_id}/responses",
            headers=headers,
            data={
                "quick_answer_id": "normal",
                "client_recorded_at": "2026-07-02T05:00:00Z",
                "client_request_id": "test-checkin-1",
            },
        )
        assert submitted.status_code == 202, submitted.text
        job_id = submitted.json()["job_id"]
        job = client.get(f"/api/v1/checkin_jobs/{job_id}", headers=headers)
        assert job.status_code == 200, job.text
        assert job.json()["status"] == "completed"
        assert job.json()["risk"]["level"] in {"normal", "attention", "intervention"}


def test_ocr_upload_poll_confirm_contract() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "staff")
        uploaded = client.post(
            "/api/v1/patients/pat_001/documents",
            headers=headers,
            data={
                "document_type": "prescription",
                "ocr_mode": "auto",
                "client_request_id": "test-doc-1",
            },
            files={"file": ("prescription.pdf", b"Metformin 500mg", "application/pdf")},
        )
        assert uploaded.status_code == 202, uploaded.text
        payload = uploaded.json()
        job = client.get(f"/api/v1/ocr/jobs/{payload['job_id']}", headers=headers)
        assert job.status_code == 200, job.text
        assert job.json()["status"] == "needs_review"

        confirmed = client.post(
            f"/api/v1/patients/pat_001/documents/{payload['upload_id']}/confirm_ocr",
            headers=headers,
            json={
                "job_id": payload["job_id"],
                "confirmed_by_user_id": "usr_demo_staff",
                "medications": [
                    {
                        "name": "Metformin",
                        "strength": "500mg",
                        "dosage": "1 viên",
                        "frequency": "2 lần/ngày",
                        "times_of_day": ["morning", "evening"],
                        "instructions": "Uống sau ăn",
                        "start_date": "2026-07-02",
                        "end_date": None,
                    }
                ],
                "follow_up": None,
                "nurse_note": "Đã đối chiếu.",
            },
        )
        assert confirmed.status_code == 200, confirmed.text
        assert confirmed.json()["document"]["status"] == "confirmed"


def test_local_notification_registration_without_apns_token() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        registered = client.post(
            "/api/v1/devices/register",
            headers=headers,
            json={
                "device_id": "ios-local-device",
                "platform": "ios",
                "notification_channel": "local",
                "role": "patient",
                "app_version": "1.0.0",
                "os_version": "15.5",
                "locale": "vi_VN",
            },
        )
        assert registered.status_code == 200, registered.text
        payload = registered.json()
        assert payload["registered"] is True
        assert payload["notification_channel"] == "local"
        assert payload["remote_push_enabled"] is False
        assert payload["updated_at"].endswith("Z")

        preferences = client.patch(
            "/api/v1/devices/ios-local-device/notification_preferences",
            headers=headers,
            json={
                "checkin_reminders_enabled": True,
                "medication_reminders_enabled": False,
                "appointment_reminders_enabled": True,
                "critical_staff_alerts_enabled": False,
            },
        )
        assert preferences.status_code == 200, preferences.text
        assert preferences.json()["preferences"]["medication_reminders_enabled"] is False

        loaded = client.get(
            "/api/v1/devices/ios-local-device/notification_preferences",
            headers=headers,
        )
        assert loaded.status_code == 200, loaded.text
        assert loaded.json()["preferences"] == preferences.json()["preferences"]


def test_error_envelope_contract() -> None:
    with TestClient(app) as client:
        response = client.get("/api/v1/me")
        assert response.status_code == 401
        body = response.json()
        assert body["error"]["code"] == "unauthorized"
        assert body["error"]["trace_id"].startswith("req_")
