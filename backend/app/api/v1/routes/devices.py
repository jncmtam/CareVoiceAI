from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_principal
from app.db.session import get_db
from app.schemas.devices import (
    DeviceRegistrationRequest,
    DeviceRegistrationResponse,
    NotificationPreferencesResponse,
    NotificationPreferencesUpdateRequest,
)
from app.services.auth import Principal
from app.services.devices import DeviceService

router = APIRouter()


@router.post("/devices/register", response_model=DeviceRegistrationResponse)
async def register_device(
    request: DeviceRegistrationRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> DeviceRegistrationResponse:
    response = await DeviceService(db).register(request, principal)
    await db.commit()
    return response


@router.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_device(
    device_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> Response:
    await DeviceService(db).delete(device_id, principal)
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get(
    "/devices/{device_id}/notification_preferences",
    response_model=NotificationPreferencesResponse,
)
async def get_preferences(
    device_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> NotificationPreferencesResponse:
    return await DeviceService(db).preferences(device_id, principal)


@router.patch(
    "/devices/{device_id}/notification_preferences",
    response_model=NotificationPreferencesResponse,
)
async def update_preferences(
    device_id: str,
    request: NotificationPreferencesUpdateRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> NotificationPreferencesResponse:
    response = await DeviceService(db).update_preferences(device_id, request, principal)
    await db.commit()
    return response
