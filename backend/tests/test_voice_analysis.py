from app.utils.voice_analysis import analysis_hints_from_transcript, enrich_checkin_summary


def test_analysis_hints_detects_pain_and_breathing() -> None:
    hints = analysis_hints_from_transcript("Hôm nay tôi đau ngực và khó thở.")
    assert hints is not None
    assert "Nội dung: đề cập đau/nhức" in hints
    assert "Nội dung: khó thở" in hints


def test_analysis_hints_returns_none_for_empty_transcript() -> None:
    assert analysis_hints_from_transcript(None) is None
    assert analysis_hints_from_transcript("   ") is None


def test_enrich_checkin_summary_appends_first_hint() -> None:
    summary = enrich_checkin_summary(
        "Đã nhận phản hồi.",
        "Tôi thấy mệt và lo lắng.",
    )
    assert summary.startswith("Đã nhận phản hồi.")
    assert "gợi ý phân tích" in summary.lower()