import uuid
from functools import lru_cache
from pathlib import Path

from pydantic import AnyHttpUrl, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "CareVoice AI API"
    app_env: str = "local"
    api_v1_prefix: str = "/api/v1"
    database_url: str = "sqlite+aiosqlite:///./carevoice.db"
    auto_create_tables: bool = True
    seed_demo_data: bool = True

    jwt_secret_key: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_seconds: int = 3600
    refresh_token_expire_days: int = 30

    cors_origins: list[str] = Field(default_factory=lambda: ["http://127.0.0.1:8000"])
    media_base_url: AnyHttpUrl | str = "http://127.0.0.1:8000"
    local_storage_dir: Path = Path("./storage")
    max_upload_bytes: int = 10 * 1024 * 1024
    max_document_upload_bytes: int = 25 * 1024 * 1024
    max_audio_upload_bytes: int = 250 * 1024 * 1024
    max_generated_media_bytes: int = 50 * 1024 * 1024
    background_job_start_delay_seconds: float = 0.15

    request_timeout_seconds: float = 20.0
    vendor_mock_mode: bool = True
    rate_limit_enabled: bool = True
    rate_limit_requests: int = 120
    rate_limit_window_seconds: int = 60

    vnpt_idg_base_url: str = "https://api.idg.vnpt.vn"
    vnpt_smartbot_base_url: str = "https://assistant-stream.vnpt.vn"

    vnpt_oauth_path: str = "auth/oauth/token"
    vnpt_oauth_username: str = ""
    vnpt_oauth_password: str = ""
    vnpt_oauth_client_id: str = ""
    vnpt_oauth_client_secret: str = ""
    vnpt_oauth_grant_type: str = "password"

    vnpt_token_id: str = ""
    vnpt_token_key: str = ""
    vnpt_access_token: str = ""
    vnpt_ekyc_token_id: str = ""
    vnpt_ekyc_token_key: str = ""
    vnpt_ekyc_access_token: str = ""
    vnpt_smartreader_token_id: str = ""
    vnpt_smartreader_token_key: str = ""
    vnpt_smartreader_access_token: str = ""
    vnpt_tts_token_id: str = ""
    vnpt_tts_token_key: str = ""
    vnpt_tts_access_token: str = ""
    vnpt_stt_token_id: str = ""
    vnpt_stt_token_key: str = ""
    vnpt_stt_access_token: str = ""
    vnpt_smartbot_token_id: str = ""
    vnpt_smartbot_token_key: str = ""
    vnpt_smartbot_access_token: str = ""
    vnpt_mac_address: str = Field(default_factory=lambda: f"carevoice-{uuid.uuid4().hex[:12]}")
    vnpt_client_session: str = Field(default_factory=lambda: f"carevoice-{uuid.uuid4().hex}")
    vnpt_client_token: str = Field(default_factory=lambda: uuid.uuid4().hex)
    vnpt_ocr_job_timeout_seconds: int = 120
    vnpt_ocr_poll_interval_seconds: float = 2.0

    vnpt_tts_model: str = "news"
    vnpt_tts_speed: float = 1.0
    vnpt_tts_region: str = "female_north"
    vnpt_tts_format: str = "mp3"

    vnpt_stt_async_duration_threshold_seconds: int = 30
    vnpt_stt_job_timeout_seconds: int = 120
    vnpt_stt_poll_interval_seconds: float = 2.0

    vnpt_smartbot_bot_id: str = ""
    vnpt_smartbot_input_channel: str = "livechat"

    redis_url: str = "redis://localhost:6379/0"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors_origins(cls, value: str | list[str]) -> list[str]:
        if isinstance(value, str):
            cleaned = value.strip()
            if cleaned.startswith("["):
                import json

                return json.loads(cleaned)
            return [origin.strip() for origin in cleaned.split(",") if origin.strip()]
        return value

    @property
    def is_production(self) -> bool:
        return self.app_env.lower() in {"prod", "production"}

    def vnpt_token_id_for(self, service: str) -> str:
        return str(getattr(self, f"vnpt_{service}_token_id", "") or self.vnpt_token_id)

    def vnpt_token_key_for(self, service: str) -> str:
        return str(getattr(self, f"vnpt_{service}_token_key", "") or self.vnpt_token_key)

    def vnpt_access_token_for(self, service: str) -> str:
        return str(getattr(self, f"vnpt_{service}_access_token", "") or self.vnpt_access_token)


@lru_cache
def get_settings() -> Settings:
    return Settings()
