from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings
from app.core.errors import APIError, ForbiddenError, UnauthorizedError
from app.core.security import (
    create_jwt,
    decode_jwt,
    hash_password,
    hash_token,
    now_utc,
    random_token_urlsafe,
    verify_password,
)
from app.models import OtpSession, Patient, PatientUser, RefreshToken, User
from app.models.enums import UserRole
from app.repositories.patients import PatientRepository
from app.repositories.users import UserRepository
from app.schemas.auth import (
    AppUser,
    AuthResponse,
    CurrentUserResponse,
    PatientSessionContext,
    RefreshTokenResponse,
)
from app.utils.ids import new_id


@dataclass(frozen=True)
class Principal:
    user_id: str
    role: UserRole
    patient_id: str | None = None

    @property
    def is_staff(self) -> bool:
        return self.role in {UserRole.nurse, UserRole.doctor, UserRole.admin}


class AuthService:
    def __init__(self, session: AsyncSession, settings: Settings) -> None:
        self.session = session
        self.settings = settings
        self.users = UserRepository(session)
        self.patients = PatientRepository(session)

    async def staff_login(self, *, login: str, password: str, device_id: str) -> AuthResponse:
        user = await self.users.by_login(login)
        if not user or user.role not in {UserRole.nurse, UserRole.doctor, UserRole.admin}:
            raise UnauthorizedError("Thông tin đăng nhập không đúng.")
        if not verify_password(password, user.hashed_password):
            raise UnauthorizedError("Thông tin đăng nhập không đúng.")
        return await self._issue_auth_response(user=user, patient=None, device_id=device_id)

    async def request_patient_otp(
        self, *, phone_number: str, patient_code: str | None
    ) -> tuple[str, str, int, int]:
        patient = await self._find_patient_for_phone(phone_number, patient_code)
        if not patient:
            raise APIError("not_found", "Không tìm thấy hồ sơ phù hợp với số điện thoại.", 404)
        code = "123456"
        otp = OtpSession(
            id=new_id("otp"),
            phone_number=phone_number,
            patient_code=patient_code,
            code_hash=hash_password(code),
            expires_at=now_utc() + timedelta(minutes=5),
            can_resend_after=now_utc() + timedelta(seconds=60),
        )
        self.session.add(otp)
        return otp.id, self._mask_phone(phone_number), 300, 60

    async def verify_patient_otp(
        self, *, otp_session_id: str, otp_code: str, device_id: str
    ) -> AuthResponse:
        otp = await self.session.get(OtpSession, otp_session_id)
        if not otp or otp.consumed_at:
            raise UnauthorizedError("OTP không hợp lệ.")
        if otp.expires_at < now_utc():
            raise APIError("otp_expired", "OTP đã hết hạn.", 410)
        otp.attempt_count += 1
        if not verify_password(otp_code, otp.code_hash):
            raise UnauthorizedError("OTP không hợp lệ.")
        patient = await self._find_patient_for_phone(otp.phone_number, otp.patient_code)
        if not patient:
            raise APIError("not_found", "Không tìm thấy bệnh nhân.", 404)
        user = await self._ensure_patient_user(patient)
        otp.consumed_at = now_utc()
        return await self._issue_auth_response(user=user, patient=patient, device_id=device_id)

    async def patient_code_login(
        self, *, patient_code: str, phone_last4: str, device_id: str
    ) -> AuthResponse:
        patient = await self.patients.by_code(patient_code)
        if not patient:
            raise APIError("not_found", "Không tìm thấy bệnh nhân.", 404)
        phones = [patient.phone_number or "", patient.caregiver_phone_number or ""]
        if not any(phone.endswith(phone_last4) for phone in phones):
            raise UnauthorizedError("Mã bệnh nhân hoặc số điện thoại không đúng.")
        user = await self._ensure_patient_user(patient)
        return await self._issue_auth_response(user=user, patient=patient, device_id=device_id)

    async def refresh(self, refresh_token: str) -> RefreshTokenResponse:
        payload = decode_jwt(refresh_token, self.settings)
        if payload.get("typ") != "refresh":
            raise UnauthorizedError()
        token_hash = hash_token(refresh_token)
        result = await self.session.execute(
            select(RefreshToken).where(RefreshToken.token_hash == token_hash)
        )
        stored = result.scalar_one_or_none()
        if not stored or stored.revoked_at or stored.expires_at < now_utc():
            raise UnauthorizedError()
        user = await self.session.get(User, stored.user_id)
        if not user or not user.is_active:
            raise UnauthorizedError()
        patient_id = await self.users.patient_id_for_user(user.id)
        stored.revoked_at = now_utc()
        access_token = create_jwt(
            settings=self.settings,
            subject=user.id,
            token_type="access",
            expires_delta=timedelta(seconds=self.settings.access_token_expire_seconds),
            role=user.role.value,
            patient_id=patient_id,
        )
        new_refresh, refresh_entity = self._new_refresh_token(user=user, device_id=stored.device_id)
        refresh_entity.rotated_from_id = stored.id
        self.session.add(refresh_entity)
        return RefreshTokenResponse(
            access_token=access_token,
            refresh_token=new_refresh,
            expires_in=self.settings.access_token_expire_seconds,
        )

    async def logout(self, *, refresh_token: str | None, device_id: str | None, user_id: str) -> None:
        if refresh_token:
            token_hash = hash_token(refresh_token)
            result = await self.session.execute(
                select(RefreshToken).where(RefreshToken.token_hash == token_hash)
            )
            stored = result.scalar_one_or_none()
            if stored:
                stored.revoked_at = now_utc()
        elif device_id:
            result = await self.session.execute(
                select(RefreshToken).where(
                    RefreshToken.user_id == user_id,
                    RefreshToken.device_id == device_id,
                    RefreshToken.revoked_at.is_(None),
                )
            )
            for token in result.scalars():
                token.revoked_at = now_utc()

    async def current_user_response(self, principal: Principal) -> CurrentUserResponse:
        user = await self.session.get(User, principal.user_id)
        if not user:
            raise UnauthorizedError()
        patient = await self.session.get(Patient, principal.patient_id) if principal.patient_id else None
        return CurrentUserResponse(user=self._app_user(user), patient=self._patient_context(patient))

    async def principal_from_token(self, token: str) -> Principal:
        payload = decode_jwt(token, self.settings)
        if payload.get("typ") != "access":
            raise UnauthorizedError()
        user_id = str(payload["sub"])
        user = await self.session.get(User, user_id)
        if not user or not user.is_active or user.deleted_at:
            raise UnauthorizedError()
        role = UserRole(payload["role"])
        patient_id = payload.get("patient_id")
        return Principal(user_id=user_id, role=role, patient_id=patient_id)

    async def require_patient_scope(self, principal: Principal, patient_id: str) -> None:
        if principal.is_staff:
            return
        if principal.patient_id != patient_id:
            raise ForbiddenError()

    async def _issue_auth_response(
        self, *, user: User, patient: Patient | None, device_id: str
    ) -> AuthResponse:
        patient_id = patient.id if patient else None
        access_token = create_jwt(
            settings=self.settings,
            subject=user.id,
            token_type="access",
            expires_delta=timedelta(seconds=self.settings.access_token_expire_seconds),
            role=user.role.value,
            patient_id=patient_id,
        )
        refresh_token, refresh_entity = self._new_refresh_token(user=user, device_id=device_id)
        self.session.add(refresh_entity)
        return AuthResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=self.settings.access_token_expire_seconds,
            user=self._app_user(user),
            patient=self._patient_context(patient),
        )

    def _new_refresh_token(self, *, user: User, device_id: str | None) -> tuple[str, RefreshToken]:
        raw_token = create_jwt(
            settings=self.settings,
            subject=user.id,
            token_type="refresh",
            expires_delta=timedelta(days=self.settings.refresh_token_expire_days),
            role=user.role.value,
            jti=random_token_urlsafe(),
        )
        return raw_token, RefreshToken(
            id=new_id("rft"),
            user_id=user.id,
            device_id=device_id,
            token_hash=hash_token(raw_token),
            expires_at=now_utc() + timedelta(days=self.settings.refresh_token_expire_days),
        )

    async def _find_patient_for_phone(
        self, phone_number: str, patient_code: str | None
    ) -> Patient | None:
        stmt = select(Patient).where(
            Patient.deleted_at.is_(None),
            Patient.is_active.is_(True),
            (Patient.phone_number == phone_number) | (Patient.caregiver_phone_number == phone_number),
        )
        if patient_code:
            stmt = stmt.where(Patient.patient_code == patient_code)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def _ensure_patient_user(self, patient: Patient) -> User:
        result = await self.session.execute(
            select(User).join(PatientUser).where(PatientUser.patient_id == patient.id).limit(1)
        )
        user = result.scalar_one_or_none()
        if user:
            return user
        user = User(
            id=new_id("usr"),
            full_name=patient.full_name,
            role=UserRole.patient,
            phone_number=patient.phone_number,
            is_active=True,
        )
        link = PatientUser(id=new_id("pu"), user_id=user.id, patient_id=patient.id)
        self.session.add_all([user, link])
        return user

    def _app_user(self, user: User) -> AppUser:
        return AppUser(
            id=user.id,
            role=user.role,
            full_name=user.full_name,
            staff_code=user.staff_code,
            department=user.department,
        )

    def _patient_context(self, patient: Patient | None) -> PatientSessionContext | None:
        if not patient:
            return None
        return PatientSessionContext(
            id=patient.id, patient_code=patient.patient_code, full_name=patient.full_name
        )

    def _mask_phone(self, phone_number: str) -> str:
        return f"+84******{phone_number[-3:]}" if len(phone_number) >= 3 else phone_number

