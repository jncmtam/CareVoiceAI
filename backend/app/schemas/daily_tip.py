from datetime import date

from app.schemas.common import APIModel


class DailyTipResponse(APIModel):
    tip_date: date
    tip_text: str
    source_scope: str
    diagnoses_context: list[str] = []