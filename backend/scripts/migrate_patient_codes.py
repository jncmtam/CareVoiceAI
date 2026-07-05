"""Migrate legacy BN-YYYY-NNNN patient codes to VC-YYYY-NNNNNN."""

import asyncio
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.db.init_db import create_tables, migrate_legacy_patient_codes  # noqa: E402
from app.db.session import AsyncSessionLocal  # noqa: E402
from app.core.config import get_settings  # noqa: E402


async def main() -> None:
    settings = get_settings()
    if settings.auto_create_tables:
        await create_tables()
    async with AsyncSessionLocal() as session:
        updated = await migrate_legacy_patient_codes(session)
    print(f"Migrated {updated} patient code(s) to VC format.")


if __name__ == "__main__":
    asyncio.run(main())