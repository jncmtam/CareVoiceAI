#!/usr/bin/env python3
"""Tạo đơn thuốc mẫu .docx (Chu Minh Tâm) và in kết quả OCR mock."""

from __future__ import annotations

import json
import sys
from datetime import timedelta
from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Pt

ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "backend"
OCR_TEST_DIR = BACKEND / "test" / "ocr"
OUTPUT_DOCX = OCR_TEST_DIR / "don_thuoc_chu_minh_tam.docx"
OUTPUT_OCR = OCR_TEST_DIR / "don_thuoc_chu_minh_tam_ocr_result.json"

sys.path.insert(0, str(BACKEND))

from app.integrations.vnpt.parsers.prescription import parse_ocr_payload  # noqa: E402
from app.utils.datetime import now_utc  # noqa: E402


def build_prescription_docx(path: Path) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)

    doc = Document()
    style = doc.styles["Normal"]
    style.font.name = "Times New Roman"
    style.font.size = Pt(12)

    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = title.add_run("PHÒNG KHÁM NỘI TIẾT — BỆNH VIỆN DEMO CAREVOICE")
    run.bold = True
    run.font.size = Pt(14)

    sub = doc.add_paragraph()
    sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
    sub.add_run("ĐƠN THUỐC").bold = True

    doc.add_paragraph("")

    lines = [
        "Mã hồ sơ: VC-2026-000001",
        "Bệnh nhân: Chu Minh Tâm",
        "Ngày sinh: 15/07/1998",
        "Giới tính: Nam",
        "SĐT: 0327628468",
        "Địa chỉ: TP.HCM",
        "Chẩn đoán: Đái tháo đường type 2, Tăng huyết áp",
        "",
        "Bác sĩ: BS. Lê Minh",
        "Khoa: Nội tiết",
        "Ngày kê đơn: 05/07/2026",
        "",
        "ĐƠN THUỐC:",
        "1. Metformin 500mg — 1 viên, uống 2 lần/ngày (sáng, tối), uống sau ăn.",
        "2. Amlodipine 5mg — 1 viên mỗi sáng, uống vào cùng một giờ mỗi ngày.",
        "",
        "Tái khám Nội tiết sau 14 ngày.",
        "",
        "Dặn dò: Uống thuốc đủ liều, không tự ý ngưng thuốc. Theo dõi đường huyết buổi sáng.",
        "Nếu chóng mặt, mệt bất thường hoặc đau ngực — gọi điều dưỡng ngay.",
        "",
        "Người kê đơn: BS. Lê Minh",
    ]

    raw_text = "\n".join(lines)
    for line in lines:
        doc.add_paragraph(line)

    doc.save(path)
    return raw_text


def run_ocr_preview(raw_text: str) -> dict:
    result = parse_ocr_payload(raw_text=raw_text)
    follow_up = result.draft_follow_up or {}
    if follow_up.get("appointment_at") is None:
        follow_up = {
            **follow_up,
            "appointment_at": (now_utc() + timedelta(days=14)).isoformat(),
        }
    return {
        "raw_text": result.raw_text,
        "draft_patient": result.draft_patient,
        "draft_medications": result.draft_medications,
        "draft_follow_up": follow_up,
        "instructions": result.instructions,
        "warnings": result.warnings,
    }


def main() -> None:
    raw_text = build_prescription_docx(OUTPUT_DOCX)
    ocr = run_ocr_preview(raw_text)
    OUTPUT_OCR.write_text(json.dumps(ocr, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"Đã tạo: {OUTPUT_DOCX}")
    print(f"Kết quả OCR: {OUTPUT_OCR}")
    print()
    print("=== KẾT QUẢ OCR (mock parser) ===")
    print(json.dumps(ocr, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()