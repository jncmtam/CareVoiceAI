from pathlib import Path

from fastapi import UploadFile

from app.core.config import Settings
from app.core.errors import APIError
from app.utils.ids import new_id

ALLOWED_UPLOAD_TYPES = {
    "application/pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/msword",
    "image/jpeg",
    "image/png",
    "image/heic",
    "audio/m4a",
    "audio/mp4",
    "audio/mpeg",
    "audio/mp3",
    "audio/wav",
    "audio/x-wav",
    "audio/ogg",
    "audio/aac",
    "audio/x-m4a",
}


class StorageService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.base_dir = settings.local_storage_dir

    def resolve_path(self, storage_url: str) -> Path:
        relative = storage_url.removeprefix("/media/").lstrip("/")
        return self.base_dir / relative

    async def read_bytes(self, storage_url: str) -> tuple[bytes, str, str]:
        path = self.resolve_path(storage_url)
        if not path.exists():
            raise APIError("not_found", "Không tìm thấy file đã lưu.", 404)
        content_type = {
            ".pdf": "application/pdf",
            ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            ".doc": "application/msword",
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".m4a": "audio/m4a",
            ".wav": "audio/wav",
            ".mp3": "audio/mpeg",
        }.get(path.suffix.lower(), "application/octet-stream")
        return path.read_bytes(), path.name, content_type

    async def save_bytes(
        self,
        *,
        folder: str,
        filename: str,
        data: bytes,
        content_type: str,
    ) -> str:
        relative_path = Path(folder) / filename
        absolute_path = self.base_dir / relative_path
        absolute_path.parent.mkdir(parents=True, exist_ok=True)
        if len(data) > self.settings.max_generated_media_bytes:
            raise APIError("file_too_large", "File vượt quá giới hạn cho phép.", 413)
        absolute_path.write_bytes(data)
        _ = content_type
        return f"/media/{relative_path.as_posix()}"

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
                if size > self._max_bytes_for_content_type(content_type):
                    absolute_path.unlink(missing_ok=True)
                    raise APIError("file_too_large", "File vượt quá giới hạn cho phép.", 413)
                target.write(chunk)

        return f"/media/{relative_path.as_posix()}", size

    def _max_bytes_for_content_type(self, content_type: str) -> int:
        if content_type.startswith("audio/"):
            return self.settings.max_audio_upload_bytes
        if content_type in {
            "application/pdf",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/msword",
            "image/jpeg",
            "image/png",
            "image/heic",
        }:
            return self.settings.max_document_upload_bytes
        return self.settings.max_upload_bytes
