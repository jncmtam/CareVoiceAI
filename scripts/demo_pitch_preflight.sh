#!/usr/bin/env bash
# Kiểm tra nhanh trước demo pitch — chạy 1–2 phút trước khi lên sân.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/backend"
PORT="${PORT:-8000}"
BASE="http://127.0.0.1:${PORT}/api/v1"
PASS=0
FAIL=0

ok() { echo "✅ $1"; PASS=$((PASS + 1)); }
warn() { echo "⚠️  $1"; }
bad() { echo "❌ $1"; FAIL=$((FAIL + 1)); }

echo "╔══════════════════════════════════════════════╗"
echo "║   CareVoice — Preflight demo pitch           ║"
echo "╚══════════════════════════════════════════════╝"
echo

# 1. Backend
if curl -sf "http://127.0.0.1:${PORT}/healthz" | grep -q '"status":"ok"'; then
  ok "Backend đang chạy (:${PORT})"
else
  bad "Backend chưa chạy — chạy: make backend"
fi

# 2. Auth
if curl -sf -X POST "$BASE/auth/patient/login" \
  -H "Content-Type: application/json" \
  -d '{"login":"patient","password":"patient","device_id":"preflight-patient"}' \
  | python3 -c "import sys,json; json.load(sys.stdin)['access_token']" >/dev/null 2>&1; then
  ok "Đăng nhập bệnh nhân patient/patient"
else
  bad "Không đăng nhập được bệnh nhân"
fi

if curl -sf -X POST "$BASE/auth/staff/login" \
  -H "Content-Type: application/json" \
  -d '{"login":"nurse","password":"nurse","device_id":"preflight-staff"}' \
  | python3 -c "import sys,json; json.load(sys.stdin)['access_token']" >/dev/null 2>&1; then
  ok "Đăng nhập điều dưỡng nurse/nurse"
else
  bad "Không đăng nhập được điều dưỡng"
fi

# 3. Demo patient (reuse token from login above)
PAT_TOKEN=$(curl -sf -X POST "$BASE/auth/patient/login" \
  -H "Content-Type: application/json" \
  -d '{"login":"patient","password":"patient","device_id":"preflight-patient"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
PAT_HDR="Authorization: Bearer ${PAT_TOKEN}"

CODE=$(curl -sf -H "$PAT_HDR" -H "Accept: application/json" "$BASE/me/patient" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['patient']['patient_code'])")
if [[ "$CODE" == "VC-2026-000001" ]]; then
  ok "Bệnh nhân demo: Chu Minh Tâm ($CODE)"
else
  bad "Mã bệnh nhân demo sai: $CODE"
fi

# 4. Check-in today
if curl -sf -H "$PAT_HDR" "$BASE/me/checkins/today" \
  | python3 -c "import sys,json; json.load(sys.stdin)['checkin']" >/dev/null 2>&1; then
  ok "Check-in hôm nay sẵn sàng"
else
  bad "Không lấy được check-in hôm nay"
fi

# 5. Daily tip
if curl -sf -H "$PAT_HDR" "$BASE/me/daily_tip" \
  | python3 -c "import sys,json; t=json.load(sys.stdin); assert t.get('tip_text')" >/dev/null 2>&1; then
  ok "Lời khuyên sức khỏe AI (daily_tip)"
else
  warn "Daily tip chưa trả — vẫn demo được phần khác"
fi

# 6. OCR fixture
OCR="$BACKEND/test/ocr/don_thuoc_chu_minh_tam.docx"
if [[ -f "$OCR" ]]; then
  ok "File OCR mẫu: don_thuoc_chu_minh_tam.docx"
else
  bad "Thiếu file OCR: $OCR"
fi

# 7. STT fixture
WAV="$BACKEND/test/stt/STT.sample.wav"
if [[ -f "$WAV" ]]; then
  ok "File WAV mẫu: STT.sample.wav"
else
  bad "Thiếu file WAV: $WAV"
fi

# 8. iOS reminder
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
echo
echo "── Nhắc iOS ──"
echo "  Simulator:  http://127.0.0.1:${PORT}/api/v1"
echo "  iPhone:     http://${IP}:${PORT}/api/v1"
echo "  Tắt Demo mode · Bật âm lượng · Đăng sẵn patient + nurse"
echo
echo "── Script pitch ──"
echo "  docs/DEMO_PITCH_SCRIPT.md"
echo

if [[ "$FAIL" -eq 0 ]]; then
  echo "══ Kết quả: $PASS OK — Sẵn sàng pitch ══"
  exit 0
else
  echo "══ Kết quả: $PASS OK, $FAIL lỗi — Sửa trước khi pitch ══"
  exit 1
fi