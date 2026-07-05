def analysis_hints_from_transcript(transcript: str | None) -> list[str] | None:
    if not transcript or not transcript.strip():
        return None
    lower = transcript.lower()
    hints: list[str] = []
    if any(token in lower for token in ("lo lắng", "lo ", "sợ", "hoảng", "run")):
        hints.append("Ngữ điệu: có dấu hiệu lo lắng")
    if any(token in lower for token in ("mệt", "uể oải", "không có sức", "kiệt")):
        hints.append("Ngữ điệu: mệt mỏi")
    if any(token in lower for token in ("đau", "nhức", "tức")):
        hints.append("Nội dung: đề cập đau/nhức")
    if any(token in lower for token in ("khó thở", "thở gấp", "ngạt")):
        hints.append("Nội dung: khó thở")
    return hints or None


def enrich_checkin_summary(summary: str, transcript: str | None) -> str:
    hints = analysis_hints_from_transcript(transcript)
    if not hints:
        return summary
    return f"{summary} Gợi ý phân tích: {hints[0].lower()}."