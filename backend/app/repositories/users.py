from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import PatientUser, User
from app.models.enums import UserRole
from app.repositories.base import Repository


class UserRepository(Repository[User]):
    def __init__(self, session: AsyncSession) -> None:
        super().__init__(session, User)

    async def by_login(self, login: str) -> User | None:
        result = await self.session.execute(
            select(User).where(
                User.deleted_at.is_(None),
                User.is_active.is_(True),
                or_(User.email == login, User.staff_code == login),
            )
        )
        return result.scalar_one_or_none()

    async def by_phone_role(self, phone_number: str, role: UserRole) -> User | None:
        result = await self.session.execute(
            select(User).where(
                User.deleted_at.is_(None),
                User.is_active.is_(True),
                User.phone_number == phone_number,
                User.role == role,
            )
        )
        return result.scalar_one_or_none()

    async def patient_id_for_user(self, user_id: str) -> str | None:
        result = await self.session.execute(
            select(PatientUser.patient_id).where(PatientUser.user_id == user_id).limit(1)
        )
        return result.scalar_one_or_none()

