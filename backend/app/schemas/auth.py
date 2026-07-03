from pydantic import Field

from app.models.enums import UserRole
from app.schemas.common import APIModel


class StaffLoginRequest(APIModel):
    login: str = Field(min_length=1, max_length=255)
    password: str = Field(min_length=1, max_length=255)
    device_id: str = Field(min_length=1, max_length=255)


class PatientOtpRequest(APIModel):
    phone_number: str = Field(min_length=8, max_length=32)
    patient_code: str | None = Field(default=None, max_length=64)


class PatientOtpResponse(APIModel):
    otp_session_id: str
    masked_phone_number: str
    expires_in: int
    can_resend_after: int


class PatientOtpVerifyRequest(APIModel):
    otp_session_id: str
    otp_code: str = Field(min_length=4, max_length=8)
    device_id: str = Field(min_length=1, max_length=255)


class PatientCodeLoginRequest(APIModel):
    patient_code: str
    phone_last4: str = Field(min_length=4, max_length=4)
    device_id: str = Field(min_length=1, max_length=255)


class RefreshTokenRequest(APIModel):
    refresh_token: str


class LogoutRequest(APIModel):
    device_id: str | None = None
    refresh_token: str | None = None


class AppUser(APIModel):
    id: str
    role: UserRole
    full_name: str
    staff_code: str | None = None
    department: str | None = None


class PatientSessionContext(APIModel):
    id: str
    patient_code: str
    full_name: str


class AuthResponse(APIModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: AppUser
    patient: PatientSessionContext | None = None


class RefreshTokenResponse(APIModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class CurrentUserResponse(APIModel):
    user: AppUser
    patient: PatientSessionContext | None = None

