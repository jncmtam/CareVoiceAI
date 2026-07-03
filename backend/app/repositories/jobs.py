from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Job
from app.repositories.base import Repository


class JobRepository(Repository[Job]):
    def __init__(self, session: AsyncSession) -> None:
        super().__init__(session, Job)

    async def by_source(self, source_id: str) -> Job | None:
        result = await self.session.execute(select(Job).where(Job.source_id == source_id))
        return result.scalar_one_or_none()

