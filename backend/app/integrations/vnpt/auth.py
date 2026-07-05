from __future__ import annotations

import time
from dataclasses import dataclass

from app.core.config import Settings
from app.integrations.vnpt.client import VNPTHttpClient, extract_object


@dataclass
class _TokenCache:
    access_token: str
    expires_at: float


class VNPTAuthService:
    def __init__(self, settings: Settings, http: VNPTHttpClient) -> None:
        self.settings = settings
        self.http = http
        self._cache: dict[str, _TokenCache] = {}

    async def access_token(self, service: str = "default") -> str:
        configured = self.settings.vnpt_access_token_for(service)
        if configured:
            return configured
        cached = self._cache.get(service)
        if cached and cached.expires_at > time.time():
            return cached.access_token
        if not self._can_request_oauth_token():
            return ""

        body = self._oauth_body()
        payload = await self.http.request_json(
            method="POST",
            base_url=self.settings.vnpt_idg_base_url,
            path=self.settings.vnpt_oauth_path,
            token_id="",
            token_key="",
            access_token="",
            json_body=body,
            include_mac=False,
        )
        obj = extract_object(payload)
        token = str(obj.get("access_token") or payload.get("access_token") or "")
        if not token:
            raise ValueError("VNPT oauth/token không trả access_token.")
        expires_in = int(obj.get("expires_in") or payload.get("expires_in") or 3600)
        self._cache[service] = _TokenCache(access_token=token, expires_at=time.time() + max(expires_in - 60, 60))
        return token

    def _can_request_oauth_token(self) -> bool:
        if not self.settings.vnpt_oauth_client_id or not self.settings.vnpt_oauth_client_secret:
            return False
        if self.settings.vnpt_oauth_grant_type == "password":
            return bool(self.settings.vnpt_oauth_username and self.settings.vnpt_oauth_password)
        return True

    def _oauth_body(self) -> dict[str, str]:
        body = {
            "grant_type": self.settings.vnpt_oauth_grant_type,
            "client_id": self.settings.vnpt_oauth_client_id,
            "client_secret": self.settings.vnpt_oauth_client_secret,
        }
        if self.settings.vnpt_oauth_username:
            body["username"] = self.settings.vnpt_oauth_username
        if self.settings.vnpt_oauth_password:
            body["password"] = self.settings.vnpt_oauth_password
        return body
