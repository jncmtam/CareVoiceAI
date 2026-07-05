#!/usr/bin/env bash
# Gán IP Mac hiện tại vào app iOS để iPhone thật trỏ đúng backend local.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${1:-8000}"

IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
if [[ -z "${IP}" ]]; then
  IP="$(ipconfig getifaddr en1 2>/dev/null || true)"
fi
if [[ -z "${IP}" ]]; then
  echo "❌ Không lấy được IP Wi-Fi. Bật Wi-Fi trên Mac rồi chạy lại." >&2
  exit 1
fi

API_URL="http://${IP}:${PORT}/api/v1"
MEDIA_URL="http://${IP}:${PORT}"

PLIST="${ROOT}/CareVoiceAI/Resources/Info.plist"
CONSTANTS="${ROOT}/CareVoiceAI/App/AppConstants.swift"

/usr/libexec/PlistBuddy -c "Set :CAREVOICE_API_BASE_URL ${API_URL}" "${PLIST}"

python3 - "${CONSTANTS}" "${API_URL}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
url = sys.argv[2]
text = path.read_text(encoding="utf-8")
updated, count = re.subn(
    r'static let defaultBaseURL = "http://[^"]+/api/v1"',
    f'static let defaultBaseURL = "{url}"',
    text,
    count=1,
)
if count != 1:
    raise SystemExit("Could not update AppConstants.defaultBaseURL")
path.write_text(updated, encoding="utf-8")
PY

echo ""
echo "✅ Đã cập nhật URL backend cho iPhone:"
echo "   API:   ${API_URL}"
echo "   Media: ${MEDIA_URL}"
echo ""
echo "Tiếp theo:"
echo "  1. Xcode → Product → Clean Build Folder"
echo "  2. Build & Run lên iPhone (cắm cáp hoặc wireless)"
echo "  3. iPhone và Mac cùng Wi-Fi; cho phép「Mạng cục bộ」khi app hỏi"
echo ""
echo "Nếu dùng Docker và cần audio TTS trên iPhone, restart API với:"
echo "  cd backend && MEDIA_BASE_URL=${MEDIA_URL} docker compose up -d --force-recreate api"
echo ""