import os

import pytest

from app.core.config import get_settings

_DEFAULT_LIMITS = {
    "MAX_DOCUMENT_UPLOAD_BYTES": "26214400",
    "MAX_AUDIO_UPLOAD_BYTES": "262144000",
    "MAX_GENERATED_MEDIA_BYTES": "52428800",
    "MAX_UPLOAD_BYTES": "10485760",
}


@pytest.fixture(autouse=True)
def _restore_upload_limits(monkeypatch: pytest.MonkeyPatch) -> None:
    """Tránh test storage_limits làm ô nhiễm env cho các test khác."""
    for key, value in _DEFAULT_LIMITS.items():
        monkeypatch.setenv(key, value)
    get_settings.cache_clear()