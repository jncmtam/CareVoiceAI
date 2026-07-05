from __future__ import annotations

import re
from datetime import datetime, timezone

from app.core.errors import APIError

PATIENT_CODE_PREFIX = "VC"
PATIENT_CODE_PATTERN = re.compile(r"^VC-\d{4}-\d{6}$")
LEGACY_BN_PATTERN = re.compile(r"^BN-(\d{4})-(\d+)$")
VN_MOBILE_PATTERN = re.compile(r"^\+84[3-9]\d{8}$")


def normalize_patient_code(value: str) -> str:
    return value.strip().upper()


def normalize_phone_number(value: str) -> str:
    cleaned = re.sub(r"[\s\-.()]+", "", value.strip())
    if cleaned.startswith("00"):
        cleaned = "+" + cleaned[2:]
    if cleaned.startswith("+"):
        digits = "+" + re.sub(r"\D", "", cleaned[1:])
        return digits
    digits = re.sub(r"\D", "", cleaned)
    if digits.startswith("84"):
        return f"+{digits}"
    if digits.startswith("0") and len(digits) == 10:
        return f"+84{digits[1:]}"
    if len(digits) == 9 and digits[0] in "35789":
        return f"+84{digits}"
    return f"+{digits}" if digits else ""


def generate_patient_code(sequence: int, year: int | None = None) -> str:
    resolved_year = year or datetime.now(timezone.utc).year
    return f"{PATIENT_CODE_PREFIX}-{resolved_year}-{sequence:06d}"


def legacy_patient_code_to_vc(code: str) -> str | None:
    normalized = normalize_patient_code(code)
    match = LEGACY_BN_PATTERN.fullmatch(normalized)
    if not match:
        return None
    year = int(match.group(1))
    sequence = int(match.group(2))
    return generate_patient_code(sequence, year)


def patient_code_lookup_candidates(code: str) -> list[str]:
    normalized = normalize_patient_code(code)
    candidates: list[str] = []
    for value in (normalized, legacy_patient_code_to_vc(normalized)):
        if value and value not in candidates:
            candidates.append(value)
    return candidates


def validate_patient_code(value: str) -> str:
    code = normalize_patient_code(value)
    if not PATIENT_CODE_PATTERN.fullmatch(code):
        raise APIError(
            "validation_error",
            "Mã bệnh nhân phải theo dạng VC-YYYY-NNNNNN (ví dụ VC-2026-000001).",
            422,
            details={"patient_code": code},
        )
    return code


def validate_phone_number(value: str, *, field_name: str = "phone_number") -> str:
    normalized = normalize_phone_number(value)
    if not VN_MOBILE_PATTERN.fullmatch(normalized):
        raise APIError(
            "validation_error",
            "Số điện thoại không hợp lệ. Dùng số Việt Nam 10 số (0xxx) hoặc +84xxx.",
            422,
            details={field_name: value},
        )
    return normalized


def validate_optional_phone_number(value: str | None, *, field_name: str) -> str | None:
    if value is None or not str(value).strip():
        return None
    return validate_phone_number(str(value), field_name=field_name)