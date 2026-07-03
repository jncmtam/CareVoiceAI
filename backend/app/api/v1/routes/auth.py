from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_principal
from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.schemas.auth import (
    AuthResponse,
    CurrentUserResponse,
    LogoutRequest,
    PatientCodeLoginRequest,
    PatientOtpRequest,
    PatientOtpResponse,
    PatientOtpVerifyRequest,
    RefreshTokenRequest,
    RefreshTokenResponse,
    StaffLoginRequest,
)
from app.services.auth import AuthService, Principal

router = APIRouter()


@router.post("/auth/staff/login", response_model=AuthResponse)
async def staff_login(
    request: StaffLoginRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AuthResponse:
    response = await AuthService(db, settings).staff_login(
        login=request.login, password=request.password, device_id=request.device_id
    )
    await db.commit()
    return response


@router.post("/auth/patient/request_otp", response_model=PatientOtpResponse)
async def request_otp(
    request: PatientOtpRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> PatientOtpResponse:
    session_id, masked, expires_in, resend_after = await AuthService(db, settings).request_patient_otp(
        phone_number=request.phone_number, patient_code=request.patient_code
    )
    await db.commit()
    return PatientOtpResponse(
        otp_session_id=session_id,
        masked_phone_number=masked,
        expires_in=expires_in,
        can_resend_after=resend_after,
    )


@router.post("/auth/patient/verify_otp", response_model=AuthResponse)
async def verify_otp(
    request: PatientOtpVerifyRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AuthResponse:
    response = await AuthService(db, settings).verify_patient_otp(
        otp_session_id=request.otp_session_id,
        otp_code=request.otp_code,
        device_id=request.device_id,
    )
    await db.commit()
    return response


@router.post("/auth/patient/login_code", response_model=AuthResponse)
async def patient_code_login(
    request: PatientCodeLoginRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AuthResponse:
    response = await AuthService(db, settings).patient_code_login(
        patient_code=request.patient_code,
        phone_last4=request.phone_last4,
        device_id=request.device_id,
    )
    await db.commit()
    return response


@router.post("/auth/refresh", response_model=RefreshTokenResponse)
async def refresh(
    request: RefreshTokenRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> RefreshTokenResponse:
    response = await AuthService(db, settings).refresh(request.refresh_token)
    await db.commit()
    return response


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    request: LogoutRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> Response:
    await AuthService(db, settings).logout(
        refresh_token=request.refresh_token,
        device_id=request.device_id,
        user_id=principal.user_id,
    )
    await db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=CurrentUserResponse)
async def me(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    principal: Annotated[Principal, Depends(get_current_principal)],
) -> CurrentUserResponse:
    return await AuthService(db, settings).current_user_response(principal)

