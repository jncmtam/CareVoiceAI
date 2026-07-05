#!/usr/bin/env bash
# In URL API để dán vào app iOS (Cài đặt → Kết nối backend).

set -euo pipefail

PORT="${1:-8000}"
IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
if [[ -z "${IP}" ]]; then
  IP="$(ipconfig getifaddr en1 2>/dev/null || true)"
fi
if [[ -z "${IP}" ]]; then
  IP="127.0.0.1"
  echo "⚠️  Không lấy được IP Wi-Fi. Simulator có thể dùng 127.0.0.1." >&2
fi

URL="http://${IP}:${PORT}/api/v1"
echo ""
echo "CareVoice API URL cho iPhone:"
echo "  ${URL}"
echo ""
echo "Trên iPhone: Cài đặt → Kết nối backend → tắt Demo mode → dán URL → Lưu & kiểm tra"
echo "Simulator trên Mac: có thể dùng http://127.0.0.1:${PORT}/api/v1"
echo ""