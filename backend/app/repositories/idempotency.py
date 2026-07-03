from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import IdempotencyKey
from app.repositories.base import Repository


class IdempotencyRepository(Repository[IdempotencyKey]):
    def __init__(self, session: AsyncSession) -> None:
        super().__init__(session, IdempotencyKey)

    async def get_key(
        self, *, scope: str, actor_id: str, client_request_id: str
    ) -> IdempotencyKey | None:
        result = await self.session.execute(
            select(IdempotencyKey).where(
                IdempotencyKey.scope == scope,
                IdempotencyKey.actor_id == actor_id,
                IdempotencyKey.client_request_id == client_request_id,
            )
        )
        return result.scalar_one_or_none()

