#!/usr/bin/env bash
# Kiểm tra submission: pytest + smoke + patient-flow, lặp 3 lần (yêu cầu BGK).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
BASE="http://127.0.0.1:8000/api/v1"
ROUNDS="${ROUNDS:-3}"
PORT="${PORT:-8000}"

need_api() {
  if ! curl -sf "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    echo "❌ API chưa chạy tại :${PORT}. Mở terminal khác: make backend" >&2
    exit 1
  fi
}

echo "=== CareVoice submission checks (rounds=$ROUNDS) ==="
echo

if [[ ! -d "$BACKEND/.venv" ]]; then
  echo "→ Chưa có venv, chạy make setup trước..."
  make -C "$ROOT" setup
fi

echo "→ Pytest..."
cd "$BACKEND"
.venv/bin/python -m pytest -q
echo "✅ Pytest passed"
echo

need_api

for round in $(seq 1 "$ROUNDS"); do
  echo "── Round $round/$ROUNDS ──"
  ./scripts/smoke_test_localhost.sh
  ./scripts/patient_flow_test.sh
  echo
done

echo "=== Hoàn tất: pytest + ${ROUNDS}x (smoke + patient-flow) ==="