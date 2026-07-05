from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.errors import UnauthorizedError
from app.db.session import get_db
from app.integrations.vnpt import VNPTGateway, get_vnpt_gateway
from app.models.enums import UserRole
from app.services.auth import AuthService, Principal

bearer_scheme = HTTPBearer(auto_error=False)


async def get_current_principal(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> Principal:
    if not credentials:
        raise UnauthorizedError()
    return await AuthService(db, settings).principal_from_token(credentials.credentials)


def require_roles(*roles: UserRole):
    async def checker(
        principal: Annotated[Principal, Depends(get_current_principal)],
    ) -> Principal:
        if principal.role not in roles:
            from app.core.errors import ForbiddenError

            raise ForbiddenError()
        return principal

    return checker


def vnpt_gateway_dep(
    settings: Annotated[Settings, Depends(get_settings)],
) -> VNPTGateway:
    return get_vnpt_gateway(settings)