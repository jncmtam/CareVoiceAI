import os
from pathlib import Path

TEST_DB = Path("test_carevoice.db")
TEST_DB.unlink(missing_ok=True)
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_carevoice.db"
os.environ["SEED_DEMO_DATA"] = "true"
os.environ["AUTO_CREATE_TABLES"] = "true"
os.environ["VENDOR_MOCK_MODE"] = "true"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402


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


def test_staff_dashboard_contract() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "staff")
        response = client.get("/api/v1/staff/dashboard/overview", headers=headers)
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["total_active_patients"] >= 1
        assert "updated_at" in body
        assert body["updated_at"].endswith("Z")


def test_patient_daily_tip_contract() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        first = client.get("/api/v1/me/daily_tip", headers=headers)
        assert first.status_code == 200, first.text
        body = first.json()
        assert body["tip_text"]
        assert body["tip_date"]
        assert body["source_scope"] in {"smartbot", "mock_fallback"}
        second = client.get("/api/v1/me/daily_tip", headers=headers)
        assert second.status_code == 200, second.text
        assert second.json()["tip_text"] == body["tip_text"]


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


def test_ocr_upload_docx_parses_patient_name() -> None:
    from tests.paths import test_asset

    fixture = test_asset("ocr", "don_thuoc_chu_minh_tam.docx")
    assert fixture.exists(), f"Missing fixture: {fixture}"
    with TestClient(app) as client:
        headers = auth_headers(client, "staff")
        uploaded = client.post(
            "/api/v1/patients/pat_001/documents",
            headers=headers,
            data={
                "document_type": "prescription",
                "ocr_mode": "auto",
                "client_request_id": "test-docx-chu-minh-tam",
            },
            files={
                "file": (
                    fixture.name,
                    fixture.read_bytes(),
                    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                )
            },
        )
        assert uploaded.status_code == 202, uploaded.text
        job = client.get(f"/api/v1/ocr/jobs/{uploaded.json()['job_id']}", headers=headers)
        assert job.status_code == 200, job.text
        body = job.json()
        assert body["status"] == "needs_review"
        assert body.get("draft_patient", {}).get("full_name") == "Chu Minh Tâm"
        assert len(body.get("draft_medications") or []) >= 1


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


def test_checkin_timeline_includes_audio_metadata() -> None:
    with TestClient(app) as client:
        patient_headers = auth_headers(client, "patient")
        staff_headers = auth_headers(client, "staff")
        today = client.get("/api/v1/me/checkins/today", headers=patient_headers)
        assert today.status_code == 200, today.text
        checkin_id = today.json()["checkin"]["id"]
        submitted = client.post(
            f"/api/v1/checkins/{checkin_id}/responses",
            headers=patient_headers,
            data={
                "quick_answer_id": "yes",
                "patient_declared_risk_level": "attention",
                "confirmed_transcript": "Hôm nay tôi hơi chóng mặt và đau đầu.",
                "client_recorded_at": "2026-07-02T05:00:00Z",
                "client_request_id": "test-checkin-timeline-audio",
            },
            files={"audio_file": ("answer.m4a", b"demo-checkin-audio", "audio/m4a")},
        )
        assert submitted.status_code == 202, submitted.text
        job_id = submitted.json()["job_id"]
        job = client.get(f"/api/v1/checkin_jobs/{job_id}", headers=patient_headers)
        assert job.status_code == 200, job.text
        assert job.json()["status"] == "completed"

        timeline = client.get(
            "/api/v1/staff/patients/pat_001/timeline",
            headers=staff_headers,
        )
        assert timeline.status_code == 200, timeline.text
        items = timeline.json()["items"]
        match = next((item for item in items if item.get("job_id") == job_id), None)
        assert match is not None
        assert match["quick_answer_id"] == "yes"
        assert match["patient_declared_risk_level"] == "attention"
        assert match["audio_url"]
        assert match["transcript"]
        assert match.get("analysis_hints")


def test_checkin_job_includes_analysis_hints() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        today = client.get("/api/v1/me/checkins/today", headers=headers)
        assert today.status_code == 200, today.text
        checkin_id = today.json()["checkin"]["id"]
        submitted = client.post(
            f"/api/v1/checkins/{checkin_id}/responses",
            headers=headers,
            data={
                "quick_answer_id": "yes",
                "patient_declared_risk_level": "attention",
                "confirmed_transcript": "Hôm nay tôi đau ngực và khó thở.",
                "client_recorded_at": "2026-07-02T05:00:00Z",
                "client_request_id": "test-checkin-analysis-hints",
            },
        )
        assert submitted.status_code == 202, submitted.text
        job_id = submitted.json()["job_id"]
        job = client.get(f"/api/v1/checkin_jobs/{job_id}", headers=headers)
        assert job.status_code == 200, job.text
        body = job.json()
        assert body["status"] == "completed"
        hints = body["risk"]["analysis_hints"]
        assert hints
        assert any("đau" in hint.lower() or "khó thở" in hint.lower() for hint in hints)


def test_checkin_attention_triggers_caregiver_alert_log() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        today = client.get("/api/v1/me/checkins/today", headers=headers)
        assert today.status_code == 200, today.text
        checkin_id = today.json()["checkin"]["id"]
        submitted = client.post(
            f"/api/v1/checkins/{checkin_id}/responses",
            headers=headers,
            data={
                "quick_answer_id": "yes",
                "client_recorded_at": "2026-07-02T05:00:00Z",
                "client_request_id": "test-checkin-caregiver-alert",
            },
        )
        assert submitted.status_code == 202, submitted.text
        job_id = submitted.json()["job_id"]
        job = client.get(f"/api/v1/checkin_jobs/{job_id}", headers=headers)
        assert job.status_code == 200, job.text
        body = job.json()
        assert body["status"] == "completed"
        assert body["risk"]["needs_staff_review"] is True
        assert body.get("caregiver_alert_sent_at")


def test_hotline_text_classifies_risk() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        response = client.post(
            "/api/v1/hotline/questions",
            headers=headers,
            json={
                "mode": "text",
                "text": "Tôi thấy đau ngực và khó thở, có nên uống thuốc không?",
                "client_request_id": "test-hotline-danger",
            },
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["status"] == "needs_review"
        assert body["risk_level"] == "intervention"
        assert body["needs_staff_review"] is True
        assert body["reasons"]
        assert body["transcript"]
        assert body["answer_text"]


def test_hotline_text_cerebral_hemorrhage_is_intervention() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        response = client.post(
            "/api/v1/hotline/questions",
            headers=headers,
            json={
                "mode": "text",
                "text": "Tôi bị xuất huyết não",
                "client_request_id": "test-hotline-hemorrhage",
            },
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["risk_level"] == "intervention"
        assert body["needs_staff_review"] is True


def test_hotline_text_stab_wound_is_intervention() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        response = client.post(
            "/api/v1/hotline/questions",
            headers=headers,
            json={
                "mode": "text",
                "text": "Cây đâm lủng giác mác",
                "client_request_id": "test-hotline-stab",
            },
        )
        assert response.status_code == 200, response.text
        assert response.json()["risk_level"] == "intervention"


def test_hotline_voice_returns_existing_question_without_idempotency_row() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        audio = b"hotline-voice-existing-row"
        first = client.post(
            "/api/v1/hotline/questions",
            headers=headers,
            data={
                "mode": "voice",
                "client_request_id": "test-hotline-voice-existing-row",
                "recorded_duration_seconds": "2",
            },
            files={"audio_file": ("question.m4a", audio, "audio/m4a")},
        )
        assert first.status_code == 202, first.text
        first_body = first.json()
        second = client.post(
            "/api/v1/hotline/questions",
            headers=headers,
            data={
                "mode": "voice",
                "client_request_id": "test-hotline-voice-existing-row",
                "recorded_duration_seconds": "2",
            },
            files={"audio_file": ("question.m4a", audio + b"-changed", "audio/m4a")},
        )
        assert second.status_code == 202, second.text
        assert second.json()["question_id"] == first_body["question_id"]


def test_hotline_voice_replays_same_client_request_id() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        audio = b"hotline-voice-replay-sample"
        first = client.post(
            "/api/v1/hotline/questions",
            headers=headers,
            data={
                "mode": "voice",
                "client_request_id": "test-hotline-voice-replay",
                "recorded_duration_seconds": "2",
            },
            files={"audio_file": ("question.m4a", audio, "audio/m4a")},
        )
        assert first.status_code == 202, first.text
        first_body = first.json()
        second = client.post(
            "/api/v1/hotline/questions",
            headers=headers,
            data={
                "mode": "voice",
                "client_request_id": "test-hotline-voice-replay",
                "recorded_duration_seconds": "2",
            },
            files={"audio_file": ("question.m4a", audio + b"-tail", "audio/m4a")},
        )
        assert second.status_code == 202, second.text
        second_body = second.json()
        assert second_body["question_id"] == first_body["question_id"]


def test_hotline_voice_transcribes_and_classifies() -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "patient")
        danger_audio = b"hotline-danger-audio-sample"
        response = client.post(
            "/api/v1/hotline/questions",
            headers=headers,
            data={
                "mode": "voice",
                "client_request_id": "test-hotline-voice-danger",
                "recorded_duration_seconds": "2",
            },
            files={"audio_file": ("question.m4a", danger_audio, "audio/m4a")},
        )
        assert response.status_code == 202, response.text
        question_id = response.json()["question_id"]
        status = client.get(f"/api/v1/hotline/questions/{question_id}", headers=headers)
        assert status.status_code == 200, status.text
        body = status.json()
        assert body["status"] in {"completed", "needs_review"}
        assert body["transcript"]
        assert body["risk_level"] in {"normal", "attention", "intervention"}
        assert body.get("reasons") is not None


def test_error_envelope_contract() -> None:
    with TestClient(app) as client:
        response = client.get("/api/v1/me")
        assert response.status_code == 401
        body = response.json()
        assert body["error"]["code"] == "unauthorized"
        assert body["error"]["trace_id"].startswith("req_")
