from pathlib import Path

from fastapi import UploadFile

from app.core.config import Settings
from app.core.errors import APIError
from app.utils.ids import new_id

ALLOWED_UPLOAD_TYPES = {
    "application/pdf",
    "image/jpeg",
    "image/png",
    "image/heic",
    "audio/m4a",
    "audio/mp4",
    "audio/mpeg",
    "audio/wav",
    "audio/x-wav",
}


class StorageService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.base_dir = settings.local_storage_dir

    async def save_upload(self, upload: UploadFile, *, folder: str) -> tuple[str, int]:
        content_type = upload.content_type or "application/octet-stream"
        if content_type not in ALLOWED_UPLOAD_TYPES:
            raise APIError(
                "unsupported_media_type",
                "Định dạng file không được hỗ trợ.",
                415,
                {"content_type": content_type},
            )

        suffix = Path(upload.filename or "").suffix.lower()
        relative_path = Path(folder) / f"{new_id('file')}{suffix}"
        absolute_path = self.base_dir / relative_path
        absolute_path.parent.mkdir(parents=True, exist_ok=True)

        size = 0
        with absolute_path.open("wb") as target:
            while chunk := await upload.read(1024 * 1024):
                size += len(chunk)
                if size > self.settings.max_upload_bytes:
                    absolute_path.unlink(missing_ok=True)
                    raise APIError("file_too_large", "File vượt quá giới hạn cho phép.", 413)
                target.write(chunk)

        return f"/media/{relative_path.as_posix()}", size

