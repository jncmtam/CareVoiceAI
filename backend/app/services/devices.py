from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Device
from app.models.enums import PushEnvironment
from app.schemas.devices import (
    DeviceRegistrationRequest,
    DeviceRegistrationResponse,
    NotificationChannel,
    NotificationPreferences,
    NotificationPreferencesResponse,
    NotificationPreferencesUpdateRequest,
)
from app.services.auth import Principal
from app.utils.datetime import now_utc
from app.utils.ids import new_id


class DeviceService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def register(
        self, request: DeviceRegistrationRequest, principal: Principal
    ) -> DeviceRegistrationResponse:
        channel = request.notification_channel or (
            NotificationChannel.apns if request.device_token else NotificationChannel.local
        )
        result = await self.session.execute(
            select(Device).where(
                Device.device_id == request.device_id,
                Device.user_id == principal.user_id,
                Device.deleted_at.is_(None),
            )
        )
        device = result.scalar_one_or_none()
        if not device:
            device = Device(
                id=new_id("dev"),
                device_id=request.device_id,
                user_id=principal.user_id,
                role=request.role,
            )
            self.session.add(device)
        device.device_token = request.device_token if channel == NotificationChannel.apns else None
        device.platform = request.platform
        device.push_environment = request.push_environment or PushEnvironment.sandbox
        device.role = request.role
        device.app_version = request.app_version
        device.os_version = request.os_version
        device.locale = request.locale
        remote_push_enabled = channel == NotificationChannel.apns and bool(device.device_token)
        return DeviceRegistrationResponse(
            device_id=device.device_id,
            registered=True,
            notification_channel=channel,
            remote_push_enabled=remote_push_enabled,
            message=self._registration_message(channel=channel, remote_push_enabled=remote_push_enabled),
            updated_at=now_utc(),
        )

    async def delete(self, device_id: str, principal: Principal) -> None:
        result = await self.session.execute(
            select(Device).where(Device.device_id == device_id, Device.user_id == principal.user_id)
        )
        for device in result.scalars():
            device.deleted_at = now_utc()
            device.device_token = None

    async def preferences(
        self,
        device_id: str,
        principal: Principal,
    ) -> NotificationPreferencesResponse:
        device = await self._active_device(device_id, principal)
        if not device:
            return NotificationPreferencesResponse(
                device_id=device_id,
                preferences=NotificationPreferences(
                    checkin_reminders_enabled=True,
                    medication_reminders_enabled=True,
                    appointment_reminders_enabled=True,
                    critical_staff_alerts_enabled=True,
                ),
            )
        return self._preferences_response(device)

    async def update_preferences(
        self,
        device_id: str,
        request: NotificationPreferencesUpdateRequest,
        principal: Principal,
    ) -> NotificationPreferencesResponse:
        result = await self.session.execute(
            select(Device).where(
                Device.device_id == device_id,
                Device.user_id == principal.user_id,
                Device.deleted_at.is_(None),
            )
        )
        device = result.scalar_one_or_none()
        if not device:
            device = Device(
                id=new_id("dev"),
                device_id=device_id,
                user_id=principal.user_id,
                role=principal.role,
                platform="ios",
                device_token=None,
            )
            self.session.add(device)
        device.checkin_reminders_enabled = request.checkin_reminders_enabled
        device.medication_reminders_enabled = request.medication_reminders_enabled
        device.appointment_reminders_enabled = request.appointment_reminders_enabled
        device.critical_staff_alerts_enabled = request.critical_staff_alerts_enabled
        return self._preferences_response(device)

    async def _active_device(self, device_id: str, principal: Principal) -> Device | None:
        result = await self.session.execute(
            select(Device).where(
                Device.device_id == device_id,
                Device.user_id == principal.user_id,
                Device.deleted_at.is_(None),
            )
        )
        return result.scalar_one_or_none()

    def _preferences_response(self, device: Device) -> NotificationPreferencesResponse:
        return NotificationPreferencesResponse(
            device_id=device.device_id,
            preferences=NotificationPreferences(
                checkin_reminders_enabled=device.checkin_reminders_enabled,
                medication_reminders_enabled=device.medication_reminders_enabled,
                appointment_reminders_enabled=device.appointment_reminders_enabled,
                critical_staff_alerts_enabled=device.critical_staff_alerts_enabled,
            ),
        )

    def _registration_message(
        self, *, channel: NotificationChannel, remote_push_enabled: bool
    ) -> str:
        if channel == NotificationChannel.apns and remote_push_enabled:
            return "Đã đăng ký APNs. Backend có thể gửi remote push cho thiết bị này."
        if channel == NotificationChannel.web_push:
            return "Web Push cần PWA cài lên Home Screen và subscription riêng từ trình duyệt."
        return "Đã đăng ký thiết bị cho local notification. Không cần Apple Developer Program."
