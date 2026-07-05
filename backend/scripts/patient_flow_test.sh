#!/usr/bin/env bash
set -euo pipefail

BASE="http://127.0.0.1:8000/api/v1"
PASS=0
FAIL=0
DEVICE_ID="patient-flow-$(date +%s)"

ok() { echo "✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "❌ $1"; FAIL=$((FAIL + 1)); exit 1; }

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then ok "$name → HTTP $actual"; else bad "$name → expected $expected, got $actual"; fi
}

json() { python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }

echo "=============================================="
echo "  CareVoice — Test toàn bộ luồng BỆNH NHÂN"
echo "=============================================="
echo

# --- 1. Đăng nhập OTP ---
OTP_REQ=$(curl -s -w "\n%{http_code}" -X POST "$BASE/auth/patient/request_otp" \
  -H "Content-Type: application/json" \
  -d '{"phone_number":"+84327628468","patient_code":"VC-2026-000001"}')
check "1a. Xin OTP" "200" "$(echo "$OTP_REQ" | tail -n1)"
OTP_SID=$(echo "$OTP_REQ" | sed '$d' | python3 -c "import sys,json; print(json.load(sys.stdin)['otp_session_id'])")

OTP_VERIFY=$(curl -s -w "\n%{http_code}" -X POST "$BASE/auth/patient/verify_otp" \
  -H "Content-Type: application/json" \
  -d "{\"otp_session_id\":\"$OTP_SID\",\"otp_code\":\"123456\",\"device_id\":\"$DEVICE_ID\"}")
check "1b. Xác thực OTP" "200" "$(echo "$OTP_VERIFY" | tail -n1)"
PAT_BODY=$(echo "$OTP_VERIFY" | sed '$d')
PAT_TOKEN=$(echo "$PAT_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
REFRESH_TOKEN=$(echo "$PAT_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['refresh_token'])")
PATIENT_ID=$(echo "$PAT_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['patient']['id'])")
PAT_HDR="Authorization: Bearer $PAT_TOKEN"
ok "1c. Nhận token + patient_id=$PATIENT_ID"

# --- 2. Profile ---
check "2a. GET /me" "200" "$(curl -s -o /dev/null -w "%{http_code}" -H "$PAT_HDR" "$BASE/me")"
ME_ROLE=$(curl -s -H "$PAT_HDR" "$BASE/me" | python3 -c "import sys,json; print(json.load(sys.stdin)['user']['role'])")
[[ "$ME_ROLE" == "patient" ]] && ok "2b. Role = patient" || bad "Role sai: $ME_ROLE"

check "2c. GET /me/patient" "200" "$(curl -s -o /dev/null -w "%{http_code}" -H "$PAT_HDR" "$BASE/me/patient")"
PAT_CODE=$(curl -s -H "$PAT_HDR" "$BASE/me/patient" | python3 -c "import sys,json; print(json.load(sys.stdin)['patient']['patient_code'])")
[[ "$PAT_CODE" == "VC-2026-000001" ]] && ok "2d. Mã VC đúng" || bad "Mã VC sai"

# --- 3. Thuốc & tái khám ---
check "3a. GET /me/medications" "200" "$(curl -s -o /dev/null -w "%{http_code}" -H "$PAT_HDR" "$BASE/me/medications")"
MED_COUNT=$(curl -s -H "$PAT_HDR" "$BASE/me/medications" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('medications',[])))")
ok "3b. Danh sách thuốc ($MED_COUNT mục)"

check "3c. GET /me/appointments" "200" "$(curl -s -o /dev/null -w "%{http_code}" -H "$PAT_HDR" "$BASE/me/appointments")"
APPT_COUNT=$(curl -s -H "$PAT_HDR" "$BASE/me/appointments" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('appointments',[])))")
ok "3d. Lịch tái khám ($APPT_COUNT mục)"

# --- 4. Check-in hôm nay ---
TODAY=$(curl -s -w "\n%{http_code}" -H "$PAT_HDR" "$BASE/me/checkins/today")
check "4a. GET /me/checkins/today" "200" "$(echo "$TODAY" | tail -n1)"
TODAY_BODY=$(echo "$TODAY" | sed '$d')
CHK_ID=$(echo "$TODAY_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['checkin']['id'])")
AUDIO_STATUS=$(echo "$TODAY_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['checkin']['audio_status'])")
ok "4b. Check-in id=$CHK_ID, audio=$AUDIO_STATUS"

# Poll audio TTS nếu đang generating
if [[ "$AUDIO_STATUS" == "generating" ]]; then
  for _ in $(seq 1 15); do
    AUDIO=$(curl -s -H "$PAT_HDR" "$BASE/checkins/$CHK_ID/audio")
    AUDIO_STATUS=$(echo "$AUDIO" | python3 -c "import sys,json; print(json.load(sys.stdin)['audio_status'])")
    [[ "$AUDIO_STATUS" == "ready" ]] && break
    sleep 0.2
  done
fi
check "4c. GET /checkins/{id}/audio" "200" "$(curl -s -o /dev/null -w "%{http_code}" -H "$PAT_HDR" "$BASE/checkins/$CHK_ID/audio")"
[[ "$AUDIO_STATUS" == "ready" ]] && ok "4d. Audio TTS sẵn sàng" || ok "4d. Audio status=$AUDIO_STATUS"

# Gửi quick answer
SUBMIT_Q=$(curl -s -w "\n%{http_code}" -X POST "$BASE/checkins/$CHK_ID/responses" \
  -H "$PAT_HDR" \
  -F "quick_answer_id=no" \
  -F "client_recorded_at=2026-07-05T09:00:00Z" \
  -F "client_request_id=pat-flow-quick-$(date +%s)")
check "4e. Gửi quick answer" "202" "$(echo "$SUBMIT_Q" | tail -n1)"
CHK_JOB=$(echo "$SUBMIT_Q" | sed '$d' | python3 -c "import sys,json; print(json.load(sys.stdin)['job_id'])")

for _ in $(seq 1 20); do
  CJ=$(curl -s -H "$PAT_HDR" "$BASE/checkin_jobs/$CHK_JOB")
  CSTATUS=$(echo "$CJ" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  [[ "$CSTATUS" == "completed" ]] && break
  sleep 0.15
done
[[ "$CSTATUS" == "completed" ]] && ok "4f. Check-in job hoàn tất (risk=$(echo "$CJ" | python3 -c "import sys,json; j=json.load(sys.stdin); print(j.get('risk',{}).get('level','?'))"))" || bad "Check-in job chưa xong: $CSTATUS"

# Gửi bằng giọng nói (mock audio)
SUBMIT_A=$(curl -s -w "\n%{http_code}" -X POST "$BASE/checkins/$CHK_ID/responses" \
  -H "$PAT_HDR" \
  -F "recorded_duration_seconds=8" \
  -F "client_recorded_at=2026-07-05T09:05:00Z" \
  -F "client_request_id=pat-flow-audio-$(date +%s)" \
  -F "audio_file=@-;filename=answer.m4a;type=audio/m4a" <<< "fake-patient-audio")
check "4g. Gửi ghi âm check-in" "202" "$(echo "$SUBMIT_A" | tail -n1)"
CHK_JOB2=$(echo "$SUBMIT_A" | sed '$d' | python3 -c "import sys,json; print(json.load(sys.stdin)['job_id'])")
for _ in $(seq 1 20); do
  CJ2=$(curl -s -H "$PAT_HDR" "$BASE/checkin_jobs/$CHK_JOB2")
  CSTATUS2=$(echo "$CJ2" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  [[ "$CSTATUS2" == "completed" ]] && break
  sleep 0.15
done
[[ "$CSTATUS2" == "completed" ]] && ok "4h. Job ghi âm hoàn tất" || bad "Job ghi âm chưa xong"

check "4i. GET /me/checkins/history" "200" "$(curl -s -o /dev/null -w "%{http_code}" -H "$PAT_HDR" "$BASE/me/checkins/history?limit=10")"
HIST_COUNT=$(curl -s -H "$PAT_HDR" "$BASE/me/checkins/history?limit=10" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items',[])))")
ok "4j. Lịch sử check-in ($HIST_COUNT mục)"

# --- 5. Hotline ---
HOT_TEXT=$(curl -s -w "\n%{http_code}" -X POST "$BASE/hotline/questions" \
  -H "$PAT_HDR" -H "Content-Type: application/json" \
  -d "{\"mode\":\"text\",\"text\":\"Hom nay toi thay hoi met, co can goi dieu duong khong?\",\"client_request_id\":\"pat-hot-text-$(date +%s)\"}")
check "5a. Hotline hỏi bằng chữ" "200" "$(echo "$HOT_TEXT" | tail -n1)"
HOT_TEXT_BODY=$(echo "$HOT_TEXT" | sed '$d')
echo "$HOT_TEXT_BODY" | python3 -c "import sys,json; j=json.load(sys.stdin); assert j.get('answer_text'); print('answer ok')"
ok "5b. Nhận câu trả lời hotline text"

HOT_VOICE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/hotline/questions" \
  -H "$PAT_HDR" \
  -F "mode=voice" \
  -F "recorded_duration_seconds=6" \
  -F "client_request_id=pat-hot-voice-$(date +%s)" \
  -F "audio_file=@-;filename=hotline.m4a;type=audio/m4a" <<< "fake-hotline-audio")
HOT_V_CODE=$(echo "$HOT_VOICE" | tail -n1)
[[ "$HOT_V_CODE" == "200" || "$HOT_V_CODE" == "202" ]] && ok "5c. Hotline hỏi bằng giọng → HTTP $HOT_V_CODE" || bad "Hotline voice failed"
HOT_QID=$(echo "$HOT_VOICE" | sed '$d' | python3 -c "import sys,json; print(json.load(sys.stdin)['question_id'])")

for _ in $(seq 1 20); do
  HQ=$(curl -s -H "$PAT_HDR" "$BASE/hotline/questions/$HOT_QID")
  HSTATUS=$(echo "$HQ" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  [[ "$HSTATUS" == "completed" ]] && break
  sleep 0.15
done
[[ "$HSTATUS" == "completed" ]] && ok "5d. Hotline voice poll → completed" || bad "Hotline voice poll: $HSTATUS"

check "5e. GET /hotline/questions (lịch sử)" "200" "$(curl -s -o /dev/null -w "%{http_code}" -H "$PAT_HDR" "$BASE/hotline/questions?limit=10")"
HOT_HIST=$(curl -s -H "$PAT_HDR" "$BASE/hotline/questions?limit=10" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('items',[])))")
ok "5f. Lịch sử hotline ($HOT_HIST mục)"

# --- 6. Thông báo / thiết bị ---
DEV=$(curl -s -w "\n%{http_code}" -X POST "$BASE/devices/register" \
  -H "$PAT_HDR" -H "Content-Type: application/json" \
  -d "{\"device_id\":\"$DEVICE_ID\",\"platform\":\"ios\",\"notification_channel\":\"local\",\"role\":\"patient\",\"app_version\":\"1.0.0\",\"os_version\":\"15.5\",\"locale\":\"vi_VN\"}")
check "6a. Đăng ký thiết bị (local notification)" "200" "$(echo "$DEV" | tail -n1)"
echo "$DEV" | sed '$d' | python3 -c "import sys,json; j=json.load(sys.stdin); assert j['notification_channel']=='local'; assert j['remote_push_enabled']==False"
ok "6b. Kênh local, không cần APNs"

check "6c. GET notification_preferences" "200" "$(curl -s -o /dev/null -w "%{http_code}" -H "$PAT_HDR" "$BASE/devices/$DEVICE_ID/notification_preferences")"

PREF=$(curl -s -w "\n%{http_code}" -X PATCH "$BASE/devices/$DEVICE_ID/notification_preferences" \
  -H "$PAT_HDR" -H "Content-Type: application/json" \
  -d '{"checkin_reminders_enabled":true,"medication_reminders_enabled":true,"appointment_reminders_enabled":false,"critical_staff_alerts_enabled":true}')
check "6d. PATCH notification_preferences" "200" "$(echo "$PREF" | tail -n1)"
echo "$PREF" | sed '$d' | python3 -c "import sys,json; j=json.load(sys.stdin); assert j['preferences']['appointment_reminders_enabled']==False"
ok "6e. Đã lưu tuỳ chọn nhắc tái khám = false"

# --- 7. eKYC placeholder ---
FACE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/identity/face_verification/sessions" \
  -H "$PAT_HDR" -H "Content-Type: application/json" \
  -d "{\"patient_id\":\"$PATIENT_ID\",\"purpose\":\"follow_up_visit\"}")
check "7a. Tạo phiên xác thực khuôn mặt" "201" "$(echo "$FACE" | tail -n1)"
FACE_ID=$(echo "$FACE" | sed '$d' | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])")
check "7b. GET trạng thái face session" "200" "$(curl -s -o /dev/null -w "%{http_code}" -H "$PAT_HDR" "$BASE/identity/face_verification/sessions/$FACE_ID")"
ok "7c. Face session id=$FACE_ID"

# --- 8. Refresh token ---
REF=$(curl -s -w "\n%{http_code}" -X POST "$BASE/auth/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}")
check "8a. Refresh token" "200" "$(echo "$REF" | tail -n1)"
NEW_TOKEN=$(echo "$REF" | sed '$d' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
NEW_REFRESH=$(echo "$REF" | sed '$d' | python3 -c "import sys,json; print(json.load(sys.stdin)['refresh_token'])")
PAT_HDR="Authorization: Bearer $NEW_TOKEN"
ok "8b. Nhận access token mới"

# --- 9. Kiểm tra quyền (bệnh nhân KHÔNG được vào staff) ---
check "9a. Dashboard staff → 403" "403" "$(curl -s -o /dev/null -w "%{http_code}" -H "$PAT_HDR" "$BASE/staff/dashboard/overview")"
check "9b. Upload OCR → 403" "403" "$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/patients/$PATIENT_ID/documents" -H "$PAT_HDR" -F "document_type=prescription" -F "ocr_mode=auto" -F "client_request_id=deny" -F "file=@-;filename=x.pdf;type=application/pdf" <<< "x")"
ok "9c. RBAC đúng — bệnh nhân không upload OCR"

# --- 10. Logout & gỡ thiết bị ---
check "10a. DELETE device" "204" "$(curl -s -o /dev/null -w "%{http_code}" -X DELETE -H "$PAT_HDR" "$BASE/devices/$DEVICE_ID")"
LOGOUT=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/auth/logout" \
  -H "$PAT_HDR" -H "Content-Type: application/json" \
  -d "{\"device_id\":\"$DEVICE_ID\",\"refresh_token\":\"$NEW_REFRESH\"}")
check "10b. Logout" "204" "$LOGOUT"

# JWT access vẫn hợp lệ đến hết TTL; refresh token bị revoke sau logout
check "10c. Refresh sau logout → 401" "401" "$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/auth/refresh" -H "Content-Type: application/json" -d "{\"refresh_token\":\"$NEW_REFRESH\"}")"

echo
echo "=============================================="
echo "  KẾT QUẢ BỆNH NHÂN: $PASS passed, $FAIL failed"
echo "=============================================="