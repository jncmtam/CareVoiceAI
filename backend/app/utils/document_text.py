from __future__ import annotations

import io


def extract_document_text(*, file_bytes: bytes, filename: str, content_type: str | None) -> str:
    name = (filename or "").lower()
    ctype = (content_type or "").lower()

    if name.endswith(".docx") or "wordprocessingml" in ctype:
        try:
            from docx import Document

            document = Document(io.BytesIO(file_bytes))
            lines = [paragraph.text.strip() for paragraph in document.paragraphs if paragraph.text.strip()]
            return "\n".join(lines)
        except Exception:
            return ""

    if name.endswith(".txt"):
        try:
            return file_bytes.decode("utf-8")
        except UnicodeDecodeError:
            return file_bytes.decode("utf-8", errors="ignore")

    return ""