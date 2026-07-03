from datetime import UTC, date, datetime
from typing import Any, Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field, field_serializer


def isoformat_utc(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


class APIModel(BaseModel):
    model_config = ConfigDict(
        from_attributes=True,
        use_enum_values=True,
    )

    @field_serializer("*", when_used="json", check_fields=False)
    def serialize_common_types(self, value):
        if isinstance(value, datetime):
            return isoformat_utc(value)
        if isinstance(value, date):
            return value.isoformat()
        return value


class APIErrorBody(APIModel):
    code: str
    message: str
    details: dict[str, str] = Field(default_factory=dict)
    trace_id: str | None = None


class APIErrorEnvelope(APIModel):
    error: APIErrorBody


ItemT = TypeVar("ItemT")


class PaginatedResponse(APIModel, Generic[ItemT]):
    items: list[ItemT]
    page: int | None = None
    per_page: int | None = None
    total: int | None = None
    has_next: bool | None = None
    next_cursor: str | None = None


class HealthResponse(APIModel):
    status: str
    app: str
    environment: str
    checked_at: datetime


def stringify_details(details: dict[str, Any] | None) -> dict[str, str]:
    if not details:
        return {}
    return {str(key): str(value) for key, value in details.items()}
