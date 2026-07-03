from dataclasses import dataclass, field
from typing import Any


@dataclass
class APIError(Exception):
    code: str
    message: str
    status_code: int
    details: dict[str, Any] = field(default_factory=dict)


class UnauthorizedError(APIError):
    def __init__(self, message: str = "Phiên đăng nhập không hợp lệ.") -> None:
        super().__init__("unauthorized", message, 401)


class ForbiddenError(APIError):
    def __init__(self, message: str = "Bạn không có quyền thực hiện thao tác này.") -> None:
        super().__init__("forbidden", message, 403)

