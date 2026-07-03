import hashlib
from datetime import timedelta
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import IdempotencyKey
from app.repositories.idempotency import IdempotencyRepository
from app.utils.datetime import now_utc
from app.utils.ids import new_id


def request_hash(payload: dict[str, Any]) -> str:
    raw = repr(sorted(payload.items())).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


class IdempotencyService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = IdempotencyRepository(session)

    async def get_replay(
        self, *, scope: str, actor_id: str, client_request_id: str, request_hash_value: str
    ) -> dict[str, Any] | None:
        existing = await self.repo.get_key(
            scope=scope, actor_id=actor_id, client_request_id=client_request_id
        )
        if not existing:
            return None
        if existing.request_hash != request_hash_value:
            return {
                "_conflict": True,
                "error": "client_request_id đã được dùng với nội dung khác.",
            }
        return existing.response_body

    async def store(
        self,
        *,
        scope: str,
        actor_id: str,
        client_request_id: str,
        request_hash_value: str,
        response_status: int,
        response_body: dict[str, Any],
    ) -> None:
        await self.repo.add(
            IdempotencyKey(
                id=new_id("idem"),
                scope=scope,
                actor_id=actor_id,
                client_request_id=client_request_id,
                request_hash=request_hash_value,
                response_status=response_status,
                response_body=response_body,
                expires_at=now_utc() + timedelta(days=7),
            )
        )

