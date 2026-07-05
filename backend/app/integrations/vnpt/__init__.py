from functools import lru_cache

from app.core.config import Settings, get_settings
from app.integrations.vnpt.gateway import LiveVNPTGateway, VNPTGateway
from app.integrations.vnpt.mock import MockVNPTGateway

vnpt_gateway: VNPTGateway = MockVNPTGateway()


def get_vnpt_gateway(settings: Settings | None = None) -> VNPTGateway:
    settings = settings or get_settings()
    if settings.vendor_mock_mode:
        return MockVNPTGateway()
    return LiveVNPTGateway(settings)


@lru_cache
def get_cached_vnpt_gateway() -> VNPTGateway:
    return get_vnpt_gateway(get_settings())