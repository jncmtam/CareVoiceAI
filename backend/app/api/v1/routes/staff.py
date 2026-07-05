from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_principal
from app.db.session import get_db
from app.models.enums import HandlingStatus, RiskLevel
from app.schemas.staff import (
    DashboardOverview,
    HandlingUpdateRequest,
    HandlingUpdateResponse,
    PatientTimelineResponse,
    PriorityPatientListResponse,
    StaffNotificationListResponse,
    StaffNotificationMarkAllReadResponse,
    StaffNotificationReadResponse,
)
from app.services.auth import Principal
from app.services.staff import StaffService

router = APIRouter()


@router.get("/staff/dashboard/overview", response_model=DashboardOverview)
async def dashboard_overview(
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> DashboardOverview:
    return await StaffService(db).dashboard_overview(principal)


@router.get("/staff/patients/priority", response_model=PriorityPatientListResponse)
async def priority_patients(
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    risk_level: RiskLevel | None = None,
    handling_status: HandlingStatus | None = None,
    actionable_only: bool = False,
    query: str | None = None,
    page: int = 1,
    per_page: int = 30,
) -> PriorityPatientListResponse:
    return await StaffService(db).priority_patients(
        principal=principal,
        page=page,
        per_page=per_page,
        query=query,
        risk_level=risk_level,
        handling_status=handling_status,
        actionable_only=actionable_only,
    )


@router.get("/staff/patients/{patient_id}/timeline", response_model=PatientTimelineResponse)
async def patient_timeline(
    patient_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    limit: int = 40,
    cursor: str | None = None,
) -> PatientTimelineResponse:
    _ = cursor
    return await StaffService(db).patient_timeline(
        principal=principal,
        patient_id=patient_id,
        limit=min(max(limit, 1), 100),
    )


@router.patch(
    "/staff/patients/{patient_id}/timeline/{entry_id}/handling",
    response_model=HandlingUpdateResponse,
)
async def update_handling(
    patient_id: str,
    entry_id: str,
    request: HandlingUpdateRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> HandlingUpdateResponse:
    response = await StaffService(db).update_handling(
        principal=principal,
        patient_id=patient_id,
        entry_id=entry_id,
        request=request,
    )
    await db.commit()
    return response


@router.get("/staff/notifications", response_model=StaffNotificationListResponse)
async def staff_notifications(
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
    page: int = 1,
    per_page: int = 30,
    unread_only: bool = False,
) -> StaffNotificationListResponse:
    return await StaffService(db).notifications(
        principal=principal,
        page=page,
        per_page=per_page,
        unread_only=unread_only,
    )


@router.patch(
    "/staff/notifications/{notification_id}/read",
    response_model=StaffNotificationReadResponse,
)
async def mark_staff_notification_read(
    notification_id: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> StaffNotificationReadResponse:
    response = await StaffService(db).mark_notification_read(
        principal=principal,
        notification_id=notification_id,
    )
    await db.commit()
    return response


@router.post(
    "/staff/notifications/mark_all_read",
    response_model=StaffNotificationMarkAllReadResponse,
)
async def mark_all_staff_notifications_read(
    db: Annotated[AsyncSession, Depends(get_db)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> StaffNotificationMarkAllReadResponse:
    response = await StaffService(db).mark_all_notifications_read(principal=principal)
    await db.commit()
    return response

