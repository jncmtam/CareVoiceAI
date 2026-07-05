from app.models.enums import RiskLevel
from app.services.risk_classifier import classify_transcript, merge_risk_levels


def test_cerebral_hemorrhage_is_intervention() -> None:
    level, reasons = classify_transcript("Tôi bị xuất huyết não", source="hotline")
    assert level == RiskLevel.intervention
    assert reasons


def test_temple_stab_wound_is_intervention() -> None:
    level, reasons = classify_transcript("Cây đâm lủng giác mác", source="hotline")
    assert level == RiskLevel.intervention
    assert any("chấn thương" in reason.lower() for reason in reasons)


def test_chest_pain_still_intervention() -> None:
    level, _ = classify_transcript("Tôi thấy đau ngực và khó thở", source="checkin")
    assert level == RiskLevel.intervention


def test_merge_prefers_intervention() -> None:
    assert merge_risk_levels(RiskLevel.normal, RiskLevel.attention, RiskLevel.intervention) == RiskLevel.intervention