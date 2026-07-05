import asyncio
import os
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from app.integrations.vnpt.mock import MockVNPTGateway
from app.services.job_runner import JobRunner

TEST_DB = Path("test_background_jobs.db")
TEST_DB.unlink(missing_ok=True)
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_background_jobs.db"
os.environ["SEED_DEMO_DATA"] = "true"
os.environ["AUTO_CREATE_TABLES"] = "true"
os.environ["VENDOR_MOCK_MODE"] = "false"
os.environ["BACKGROUND_JOB_START_DELAY_SECONDS"] = "0.05"

from app.core.config import get_settings  # noqa: E402
from app.main import app  # noqa: E402

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


@pytest.mark.asyncio
async def test_job_runner_executes_enqueued_coroutine() -> None:
    done = asyncio.Event()

    async def work() -> None:
        done.set()

    runner = JobRunner()
    runner.enqueue(lambda: work(), label="unit-test", delay_seconds=0.01)
    await asyncio.wait_for(done.wait(), timeout=1.0)


@patch("app.services.checkins.get_vnpt_gateway", return_value=MockVNPTGateway())
def test_checkin_job_runs_in_background_when_vendor_live(_mock_gateway) -> None:
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
                "client_request_id": "test-checkin-bg-1",
            },
        )
        assert submitted.status_code == 202, submitted.text
        job_id = submitted.json()["job_id"]

        job = None
        for _ in range(40):
            job = client.get(f"/api/v1/checkin_jobs/{job_id}", headers=headers)
            assert job.status_code == 200, job.text
            if job.json()["status"] == "completed":
                break
            import time

            time.sleep(0.05)

        assert job is not None
        assert job.json()["status"] == "completed"
        assert job.json()["risk"]["level"] in {"normal", "attention", "intervention"}


@patch("app.services.documents.get_vnpt_gateway", return_value=MockVNPTGateway())
def test_ocr_job_runs_in_background_when_vendor_live(_mock_gateway) -> None:
    with TestClient(app) as client:
        headers = auth_headers(client, "staff")
        uploaded = client.post(
            "/api/v1/patients/pat_001/documents",
            headers=headers,
            data={
                "document_type": "prescription",
                "ocr_mode": "auto",
                "client_request_id": "test-doc-bg-1",
            },
            files={"file": ("prescription.pdf", b"Metformin 500mg", "application/pdf")},
        )
        assert uploaded.status_code == 202, uploaded.text
        job_id = uploaded.json()["job_id"]

        job = None
        for _ in range(40):
            job = client.get(f"/api/v1/ocr/jobs/{job_id}", headers=headers)
            assert job.status_code == 200, job.text
            if job.json()["status"] == "needs_review":
                break
            import time

            time.sleep(0.05)

        assert job is not None
        assert job.json()["status"] == "needs_review"