from datetime import datetime
from enum import Enum

from pydantic import Field

from app.models.enums import PushEnvironment, UserRole
from app.schemas.common import APIModel


class NotificationChannel(str, Enum):
    local = "local"
    web_push = "web_push"
    apns = "apns"


class DeviceRegistrationRequest(APIModel):
    device_id: str = Field(min_length=1, max_length=255)
    device_token: str | None = Field(default=None, min_length=1)
    platform: str = "ios"
    push_environment: PushEnvironment | None = None
    notification_channel: NotificationChannel | None = None
    role: UserRole
    app_version: str | None = None
    os_version: str | None = None
    locale: str | None = None


class DeviceRegistrationResponse(APIModel):
    device_id: str
    registered: bool
    notification_channel: NotificationChannel = NotificationChannel.local
    remote_push_enabled: bool = False
    message: str | None = None
    updated_at: datetime | None = None


class NotificationPreferences(APIModel):
    checkin_reminders_enabled: bool
    medication_reminders_enabled: bool
    appointment_reminders_enabled: bool
    critical_staff_alerts_enabled: bool


class NotificationPreferencesUpdateRequest(NotificationPreferences):
    pass


class NotificationPreferencesResponse(APIModel):
    device_id: str
    preferences: NotificationPreferences


class FaceVerificationSessionRequest(APIModel):
    patient_id: str
    purpose: str = "follow_up_visit"


class FaceVerificationSessionResponse(APIModel):
    session_id: str
    status: str
    upload_url: str | None = None
    expires_at: datetime | None = None


class FaceVerificationStatusResponse(APIModel):
    session_id: str
    status: str
    verified_at: datetime | None = None
    needs_staff_review: bool


class FaceVerificationUploadResponse(APIModel):
    session_id: str
    status: str
    verified_at: datetime | None = None
    needs_staff_review: bool
    message: str
