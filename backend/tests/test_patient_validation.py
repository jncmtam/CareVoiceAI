import os
import re
from pathlib import Path

TEST_DB = Path("test_patient_validation.db")
TEST_DB.unlink(missing_ok=True)
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_patient_validation.db"
os.environ["SEED_DEMO_DATA"] = "true"
os.environ["AUTO_CREATE_TABLES"] = "true"
os.environ["VENDOR_MOCK_MODE"] = "true"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402
from app.utils.patient_validation import (  # noqa: E402
    generate_patient_code,
    legacy_patient_code_to_vc,
    normalize_phone_number,
    patient_code_lookup_candidates,
    validate_patient_code,
    validate_phone_number,
)


def staff_headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/staff/login",
        json={"login": "nurse", "password": "nurse", "device_id": "dev-staff"},
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_patient_code_and_phone_normalization() -> None:
    assert validate_patient_code("vc-2026-000099") == "VC-2026-000099"
    assert generate_patient_code(1, 2026) == "VC-2026-000001"
    assert legacy_patient_code_to_vc("BN-2026-0001") == "VC-2026-000001"
    assert patient_code_lookup_candidates("BN-2026-0001") == [
        "BN-2026-0001",
        "VC-2026-000001",
    ]
    assert normalize_phone_number("0901234567") == "+84901234567"
    assert validate_phone_number("0901234567") == "+84901234567"


def test_create_patient_validation_and_duplicate_rules() -> None:
    with TestClient(app) as client:
        headers = staff_headers(client)
        bad_phone = client.post(
            "/api/v1/patients",
            headers=headers,
            json={
                "full_name": "Nguyễn Văn A",
                "phone_number": "123",
            },
        )
        assert bad_phone.status_code == 422, bad_phone.text

        created = client.post(
            "/api/v1/patients",
            headers=headers,
            json={
                "full_name": "Nguyễn Văn A",
                "phone_number": "0901111222",
            },
        )
        assert created.status_code == 201, created.text
        patient_code = created.json()["patient"]["patient_code"]
        assert re.fullmatch(r"VC-\d{4}-\d{6}", patient_code), patient_code

        duplicate_phone = client.post(
            "/api/v1/patients",
            headers=headers,
            json={
                "full_name": "Nguyễn Văn C",
                "phone_number": "0901111222",
            },
        )
        assert duplicate_phone.status_code == 409, duplicate_phone.text

        patient_id = created.json()["patient"]["id"]
        deleted = client.delete(f"/api/v1/patients/{patient_id}", headers=headers)
        assert deleted.status_code == 200, deleted.text
        assert deleted.json()["deleted"] is True

        recreated = client.post(
            "/api/v1/patients",
            headers=headers,
            json={
                "full_name": "Nguyễn Văn D",
                "phone_number": "0905555666",
            },
        )
        assert recreated.status_code == 201, recreated.text
        next_code = recreated.json()["patient"]["patient_code"]
        assert int(next_code.rsplit("-", 1)[-1]) > int(patient_code.rsplit("-", 1)[-1])