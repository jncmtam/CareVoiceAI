from __future__ import annotations

import re
import unicodedata

from app.models.enums import RiskLevel

# Cụm từ cấp cứu — khớp trực tiếp → intervention
_INTERVENTION_PHRASES: tuple[tuple[str, str], ...] = (
    ("xuất huyết não", "Báo xuất huyết não"),
    ("tai biến mạch máu não", "Báo tai biến mạch máu não"),
    ("đột quỵ", "Báo đột quỵ"),
    ("đột quị", "Báo đột quỵ"),
    ("đau ngực", "Báo đau ngực"),
    ("nhồi máu cơ tim", "Báo nghi ngờ nhồi máu cơ tim"),
    ("khó thở", "Báo khó thở"),
    ("thở không ra", "Báo khó thở nghiêm trọng"),
    ("ngừng thở", "Báo ngừng thở"),
    ("ngất", "Báo ngất hoặc choáng"),
    ("bất tỉnh", "Báo bất tỉnh"),
    ("mất ý thức", "Báo mất ý thức"),
    ("co giật", "Báo co giật"),
    ("chảy máu không cầm", "Báo chảy máu không cầm được"),
    ("mất máu", "Báo mất máu nhiều"),
    ("tự tử", "Báo ý định tự tử"),
    ("tự sát", "Báo ý định tự sát"),
    ("uống thuốc quá liều", "Báo nghi ngờ quá liều thuốc"),
    ("ngộ độc", "Báo nghi ngờ ngộ độc"),
)

# Chấn thương / xâm lấn
_TRAUMA_TERMS = ("đâm", "chém", "đâm chém", "lủng", "thủng", "đâm xuyên", "vết thương hở", "bị đánh", "tai nạn")
_HEAD_TERMS = ("giác mác", "thái dương", "vùng đầu", "đầu", "não", "mặt", "mũi", "mắt")

# Cần chú ý
_ATTENTION_PHRASES: tuple[tuple[str, str], ...] = (
    ("chóng mặt", "Báo chóng mặt"),
    ("mệt", "Báo mệt bất thường"),
    ("sốt", "Báo sốt"),
    ("buồn nôn", "Báo buồn nôn"),
    ("nôn", "Báo nôn"),
    ("tiêu chảy", "Báo tiêu chảy"),
    ("đau đầu", "Báo đau đầu"),
    ("đau bụng", "Báo đau bụng"),
    ("sưng", "Báo sưng"),
    ("phù", "Báo phù"),
    ("chảy máu", "Báo chảy máu"),
    ("bầm tím", "Báo bầm tím"),
    ("ngứa", "Báo ngứa"),
    ("phát ban", "Báo phát ban"),
    ("khó ngủ", "Báo khó ngủ"),
    ("mất ngủ", "Báo mất ngủ"),
    ("không ăn", "Báo ăn uống kém"),
    ("chán ăn", "Báo chán ăn"),
)


def _normalize(text: str) -> str:
    lowered = text.lower().strip()
    lowered = unicodedata.normalize("NFC", lowered)
    lowered = re.sub(r"\s+", " ", lowered)
    return lowered


def _prefix(source: str, reason: str) -> str:
    label = {
        "checkin": "Check-in",
        "hotline": "Hotline",
    }.get(source, "Hệ thống")
    if reason.startswith(("Báo ", "Check-in:", "Hotline:")):
        return reason.replace("Báo ", f"{label}: bệnh nhân báo ", 1)
    return f"{label}: {reason}"


def _match_phrases(text: str, phrases: tuple[tuple[str, str], ...]) -> list[str]:
    return [reason for phrase, reason in phrases if phrase in text]


def _has_trauma_head_injury(text: str) -> str | None:
    has_trauma = any(term in text for term in _TRAUMA_TERMS)
    has_head = any(term in text for term in _HEAD_TERMS)
    if has_trauma and has_head:
        return "Báo chấn thương vùng đầu/thái dương"
    if has_trauma and ("lủng" in text or "thủng" in text):
        return "Báo chấn thương thủng/xuyên thấu"
    return None


def classify_transcript(
    transcript: str,
    *,
    source: str = "checkin",
    quick_answer_id: str | None = None,
) -> tuple[RiskLevel, list[str]]:
    text = _normalize(transcript)
    if not text:
        if quick_answer_id == "yes":
            return RiskLevel.attention, [f"{_prefix(source, 'bệnh nhân chọn có triệu chứng bất thường')}"]
        return RiskLevel.normal, ["Không có triệu chứng cảnh báo trong phản hồi hôm nay"]

    reasons: list[str] = []

    for reason in _match_phrases(text, _INTERVENTION_PHRASES):
        reasons.append(_prefix(source, reason))

    trauma_reason = _has_trauma_head_injury(text)
    if trauma_reason:
        reasons.append(_prefix(source, trauma_reason))

    if reasons:
        return RiskLevel.intervention, reasons[:4]

    attention_reasons = _match_phrases(text, _ATTENTION_PHRASES)
    for reason in attention_reasons:
        reasons.append(_prefix(source, reason))

    if quick_answer_id == "yes":
        reasons.append(_prefix(source, "bệnh nhân chọn có triệu chứng bất thường"))

    if reasons:
        return RiskLevel.attention, reasons[:4]

    return RiskLevel.normal, ["Không có triệu chứng cảnh báo trong phản hồi hôm nay"]


def merge_risk_levels(*levels: RiskLevel | None) -> RiskLevel:
    order = {
        RiskLevel.intervention: 3,
        RiskLevel.attention: 2,
        RiskLevel.normal: 1,
    }
    resolved = [level for level in levels if level is not None]
    if not resolved:
        return RiskLevel.normal
    return max(resolved, key=lambda level: order.get(level, 0))


def risk_level_from_value(value: str | None) -> RiskLevel | None:
    if not value:
        return None
    try:
        return RiskLevel(value)
    except ValueError:
        return None