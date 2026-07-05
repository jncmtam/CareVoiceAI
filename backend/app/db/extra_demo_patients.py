from datetime import date, timedelta

from app.models import Patient, StaffAlert
from app.models.enums import Gender, HandlingStatus, RiskLevel, TimelineEntryType
from app.utils.datetime import now_utc


def build_extra_demo_patients(staff_id: str) -> tuple[list[Patient], list[StaffAlert]]:
    now = now_utc()
    specs = [
        ("pat_004", "VC-2026-000004", "Phạm Thị Lan", date(1952, 11, 18), Gender.female, "+84907771234", RiskLevel.attention, HandlingStatus.new),
        ("pat_005", "VC-2026-000005", "Hoàng Văn Em", date(1945, 6, 2), Gender.male, "+84905556677", RiskLevel.normal, HandlingStatus.resolved),
        ("pat_006", "VC-2026-000006", "Đỗ Minh Châu", date(1960, 4, 25), Gender.female, "+84902223344", RiskLevel.intervention, HandlingStatus.viewed),
        ("pat_007", "VC-2026-000007", "Võ Thị Nga", date(1975, 8, 30), Gender.female, "+84906665544", RiskLevel.normal, None),
        ("pat_008", "VC-2026-000008", "Bùi Văn Hùng", date(1955, 12, 9), Gender.male, "+84903332211", RiskLevel.attention, HandlingStatus.resolved),
        ("pat_009", "VC-2026-000009", "Ngô Thị Mai", date(1968, 2, 14), Gender.female, "+84909990011", RiskLevel.normal, None),
    ]
    patients: list[Patient] = []
    alerts: list[StaffAlert] = []
    for pid, code, name, dob, gender, phone, risk, handling in specs:
        display_risk = RiskLevel.attention if handling == HandlingStatus.resolved and risk == RiskLevel.intervention else (
            RiskLevel.normal if handling == HandlingStatus.resolved and risk == RiskLevel.attention else risk
        )
        patients.append(
            Patient(
                id=pid,
                patient_code=code,
                full_name=name,
                date_of_birth=dob,
                gender=gender,
                phone_number=phone,
                diagnoses=["demo_profile"],
                latest_risk_level=display_risk,
                latest_checkin_at=now - timedelta(hours=3),
                is_active=True,
                created_by_user_id=staff_id,
                notes=None,
            )
        )
        if handling in {HandlingStatus.new, HandlingStatus.viewed}:
            alerts.append(
                StaffAlert(
                    id=f"alert_{pid}",
                    patient_id=pid,
                    source_type=TimelineEntryType.checkin_response,
                    source_id=f"resp_{pid}",
                    risk_level=risk,
                    summary=f"Check-in demo cho {name}.",
                    handling_status=handling,
                    unread=handling == HandlingStatus.new,
                )
            )
    return patients, alerts