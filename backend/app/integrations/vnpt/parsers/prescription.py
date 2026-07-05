from __future__ import annotations

import re
from datetime import datetime, timedelta
from typing import Any

from app.integrations.vnpt.types import OcrResult
from app.utils.datetime import now_utc

_MED_LINE = re.compile(
    r"(?P<name>[A-Za-zÀ-ỹ][A-Za-zÀ-ỹ0-9\s\-]+?)\s+"
    r"(?P<strength>\d+(?:\.\d+)?\s?(?:mg|g|ml|mcg|iu)(?:/\d+(?:\.\d+)?\s?(?:mg|g|ml))?)",
    re.IGNORECASE,
)
_PATIENT_NAME = re.compile(
    r"(?:bệnh nhân|họ tên|họ và tên|bn)\s*[:\-]\s*(?P<name>[A-Za-zÀ-ỹ][A-Za-zÀ-ỹ ]{1,48})",
    re.IGNORECASE,
)
_PHONE = re.compile(r"(?:điện thoại|sđt|dt)\s*[:\-]?\s*(?P<phone>0\d{8,10}|\+84\d{8,10})", re.IGNORECASE)
_DOCTOR = re.compile(
    r"(?:bác sĩ khám|người kê đơn|bác sĩ|bs\.?|bác sỹ)\s*[:\-]\s*(?P<doctor>BS\.?\s*[A-Za-zÀ-ỹ][A-Za-zÀ-ỹ \.]{1,40})",
    re.IGNORECASE,
)
_INSTRUCTIONS = re.compile(
    r"(?:dặn dò|lời dặn|hướng dẫn|ghi chú)\s*[:\-]\s*(?P<text>.+)",
    re.IGNORECASE,
)
_FOLLOW_UP_DAYS = re.compile(r"(?:tái khám|tai kham|hẹn khám).*?(?:sau\s+)?(?P<days>\d+)\s*ngày", re.IGNORECASE)
_DIAGNOSIS = re.compile(r"(?:chẩn đoán|cd)\s*[:\-]\s*(?P<dx>.+)", re.IGNORECASE)


def parse_ocr_payload(*, raw_text: str, structured: dict[str, Any] | None = None) -> OcrResult:
    if structured:
        medications = _medications_from_structured(structured)
        if medications:
            return OcrResult(
                raw_text=raw_text or structured.get("text", ""),
                draft_medications=medications,
                draft_patient=_patient_from_structured(structured),
                draft_follow_up=_follow_up_from_structured(structured),
                instructions=_instructions_from_structured(structured, raw_text),
                warnings=_warnings_from_structured(structured, medications),
            )

    medications = _medications_from_text(raw_text)
    return OcrResult(
        raw_text=raw_text,
        draft_medications=medications,
        draft_patient=_patient_from_text(raw_text),
        draft_follow_up=_follow_up_from_text(raw_text),
        instructions=_instructions_from_text(raw_text),
        warnings=_warnings_from_structured({}, medications),
    )


def _medications_from_structured(structured: dict[str, Any]) -> list[dict]:
    candidates = (
        structured.get("medications")
        or structured.get("draft_medications")
        or structured.get("items")
        or structured.get("fields", {}).get("medications")
    )
    if not isinstance(candidates, list):
        return []

    results: list[dict] = []
    for item in candidates:
        if not isinstance(item, dict):
            continue
        name = item.get("name") or item.get("drug_name") or item.get("ten_thuoc")
        if not name:
            continue
        confidence = item.get("confidence") or item.get("score")
        results.append(
            {
                "name": str(name).strip(),
                "strength": item.get("strength") or item.get("ham_luong"),
                "dosage": item.get("dosage") or item.get("lieu_dung"),
                "frequency": item.get("frequency") or item.get("tan_suat"),
                "times_of_day": item.get("times_of_day") or [],
                "instructions": item.get("instructions") or item.get("huong_dan"),
                "confidence": float(confidence) if confidence is not None else 0.75,
            }
        )
    return results


def _medications_from_text(raw_text: str) -> list[dict]:
    results: list[dict] = []
    for line in raw_text.splitlines():
        line = line.strip(" •-\t")
        if not line:
            continue
        match = _MED_LINE.search(line)
        if not match:
            continue
        results.append(
            {
                "name": match.group("name").strip(),
                "strength": match.group("strength").strip(),
                "dosage": "1 viên",
                "frequency": _frequency_from_line(line),
                "times_of_day": _times_from_line(line),
                "instructions": line,
                "confidence": 0.7,
            }
        )
    return results


def _patient_from_structured(structured: dict[str, Any]) -> dict | None:
    patient = structured.get("patient") or structured.get("draft_patient")
    if isinstance(patient, dict):
        return patient
    full_name = structured.get("patient_name") or structured.get("full_name")
    if not full_name:
        return None
    return {
        "full_name": full_name,
        "phone_number": structured.get("phone_number"),
        "diagnoses": structured.get("diagnoses"),
        "address": structured.get("address"),
        "primary_doctor_name": structured.get("doctor_name") or structured.get("primary_doctor_name"),
        "confidence": structured.get("patient_confidence", 0.75),
    }


def _patient_from_text(raw_text: str) -> dict | None:
    name_match = _PATIENT_NAME.search(raw_text)
    phone_match = _PHONE.search(raw_text)
    doctor_match = _DOCTOR.search(raw_text)
    dx_match = _DIAGNOSIS.search(raw_text)
    if not any([name_match, phone_match, doctor_match, dx_match]):
        return None
    diagnoses = [dx_match.group("dx").strip()] if dx_match else None
    return {
        "full_name": name_match.group("name").strip() if name_match else None,
        "phone_number": phone_match.group("phone").strip() if phone_match else None,
        "diagnoses": diagnoses,
        "primary_doctor_name": doctor_match.group("doctor").strip() if doctor_match else None,
        "confidence": 0.72,
    }


def _follow_up_from_structured(structured: dict[str, Any]) -> dict | None:
    follow = structured.get("follow_up") or structured.get("draft_follow_up")
    if isinstance(follow, dict):
        return follow
    department = structured.get("department") or structured.get("khoa")
    doctor = structured.get("doctor_name")
    if department or doctor:
        return {
            "department": department,
            "doctor_name": doctor,
            "appointment_at": structured.get("appointment_at"),
        }
    return None


def _follow_up_from_text(raw_text: str) -> dict | None:
    lower = raw_text.lower()
    if "tái khám" not in lower and "tai kham" not in lower and "hẹn khám" not in lower:
        return None
    department = None
    for token in ("Nội tiết", "Nội khoa", "Tim mạch", "Hô hấp"):
        if token.lower() in lower:
            department = token
            break
    doctor_match = _DOCTOR.search(raw_text)
    appointment_at = None
    days_match = _FOLLOW_UP_DAYS.search(raw_text)
    if days_match:
        appointment_at = (now_utc() + timedelta(days=int(days_match.group("days")))).isoformat()
    return {
        "department": department,
        "doctor_name": doctor_match.group("doctor").strip() if doctor_match else None,
        "appointment_at": appointment_at,
    }


def _instructions_from_structured(structured: dict[str, Any], raw_text: str) -> str | None:
    instructions = structured.get("instructions") or structured.get("advice") or structured.get("dan_do")
    if instructions:
        return str(instructions).strip()
    return _instructions_from_text(raw_text)


def _instructions_from_text(raw_text: str) -> str | None:
    match = _INSTRUCTIONS.search(raw_text)
    if match:
        return match.group("text").strip()
    for line in raw_text.splitlines():
        lower = line.lower()
        if any(token in lower for token in ("không tự ý", "uống đủ", "theo d0n", "theo đơn", "tái khám")):
            return line.strip()
    return None


def _warnings_from_structured(structured: dict[str, Any], medications: list[dict]) -> list[str]:
    warnings = structured.get("warnings")
    if isinstance(warnings, list):
        return [str(item) for item in warnings]
    low_conf = [med["name"] for med in medications if med.get("confidence", 1) < 0.8]
    result: list[str] = ["Điều dưỡng kiểm tra và chỉnh sửa trước khi lưu vào hồ sơ."]
    if low_conf:
        result.append(f"Có {len(low_conf)} dòng thuốc độ tin cậy thấp, cần kiểm tra lại.")
    if not medications:
        result.append("Không trích xuất được thuốc từ OCR, điều dưỡng cần nhập tay.")
    return result


def _frequency_from_line(line: str) -> str:
    lower = line.lower()
    if "2 lần" in lower:
        return "2 lần/ngày"
    if "mỗi sáng" in lower or "buổi sáng" in lower:
        return "Mỗi sáng"
    return "Theo đơn"


def _times_from_line(line: str) -> list[str]:
    lower = line.lower()
    times: list[str] = []
    if "sáng" in lower or "morning" in lower:
        times.append("morning")
    if "trưa" in lower or "noon" in lower:
        times.append("noon")
    if "chiều" in lower or "afternoon" in lower:
        times.append("afternoon")
    if "tối" in lower or "evening" in lower:
        times.append("evening")
    return times or ["morning"]