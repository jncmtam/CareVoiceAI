from datetime import UTC, date, datetime


def now_utc() -> datetime:
    return datetime.now(UTC)


def age_from_birth_date(value: date | None) -> int | None:
    if value is None:
        return None
    today = date.today()
    return today.year - value.year - ((today.month, today.day) < (value.month, value.day))

