#!/usr/bin/env bash
# Chạy backend KHÔNG cần Docker — SQLite local, phù hợp demo + iOS.

set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-8000}"
HOST="${HOST:-0.0.0.0}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Cần python3 (khuyến nghị 3.12)." >&2
  exit 1
fi

if [[ ! -d .venv ]]; then
  echo "→ Tạo virtualenv..."
  python3 -m venv .venv
fi

echo "→ Cài dependencies..."
.venv/bin/python -m pip install -q -e ".[dev]"

# Dùng SQLite, mock VNPT — không cần Postgres/Redis
export DATABASE_URL="${DATABASE_URL:-sqlite+aiosqlite:///./carevoice.db}"
export AUTO_CREATE_TABLES="${AUTO_CREATE_TABLES:-true}"
export SEED_DEMO_DATA="${SEED_DEMO_DATA:-true}"
export VENDOR_MOCK_MODE="${VENDOR_MOCK_MODE:-true}"
export MEDIA_BASE_URL="${MEDIA_BASE_URL:-http://127.0.0.1:${PORT}}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "⚠️  Port ${PORT} đang được dùng (có thể Docker). Dừng Docker trước:" >&2
  echo "    docker compose down" >&2
  echo "    hoặc PORT=8001 ./scripts/start_local.sh" >&2
  exit 1
fi

IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")"
echo ""
echo "CareVoice API (local, không Docker)"
echo "  Simulator:  http://127.0.0.1:${PORT}/api/v1"
echo "  iPhone:     http://${IP}:${PORT}/api/v1"
echo "  OpenAPI:    http://127.0.0.1:${PORT}/api/v1/docs"
echo ""
echo "Dừng server: Ctrl+C"
echo ""

exec .venv/bin/uvicorn app.main:app --reload --host "${HOST}" --port "${PORT}"