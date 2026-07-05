#!/usr/bin/env bash
set -euo pipefail

BASE="http://127.0.0.1:8000/api/v1"
PASS=0
FAIL=0

ok() { echo "✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "❌ $1"; FAIL=$((FAIL + 1)); exit 1; }

check_status() {
  local name="$1" expected="$2" actual="$3" body="$4"
  if [[ "$actual" == "$expected" ]]; then
    ok "$name → HTTP $actual"
  else
    echo "Body: $body"
    bad "$name → expected HTTP $expected, got $actual"
  fi
}

echo "=== CareVoice localhost smoke test ==="
echo

# 0. Health
code=$(curl -s -o /tmp/cv_health.json -w "%{http_code}" "http://127.0.0.1:8000/healthz")
check_status "Health check" "200" "$code" "$(cat /tmp/cv_health.json)"
grep -q '"status":"ok"' /tmp/cv_health.json && ok "Health payload ok" || bad "Health payload invalid"

# 1. Auth staff
STAFF_LOGIN=$(curl -s -w "\n%{http_code}" -X POST "$BASE/auth/staff/login" \
  -H "Content-Type: application/json" \
  -d '{"login":"nurse","password":"nurse","device_id":"smoke-staff"}')
STAFF_BODY=$(echo "$STAFF_LOGIN" | sed '$d')
STAFF_CODE=$(echo "$STAFF_LOGIN" | tail -n1)
check_status "Staff login" "200" "$STAFF_CODE" "$STAFF_BODY"
STAFF_TOKEN=$(echo "$STAFF_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
STAFF_HDR="Authorization: Bearer $STAFF_TOKEN"
ok "Staff token received"

# 2. Auth patient
PAT_LOGIN=$(curl -s -w "\n%{http_code}" -X POST "$BASE/auth/patient/login" \
  -H "Content-Type: application/json" \
  -d '{"login":"patient","password":"patient","device_id":"smoke-patient"}')
PAT_BODY=$(echo "$PAT_LOGIN" | sed '$d')
PAT_CODE=$(echo "$PAT_LOGIN" | tail -n1)
check_status "Patient login" "200" "$PAT_CODE" "$PAT_BODY"
PAT_TOKEN=$(echo "$PAT_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
PAT_HDR="Authorization: Bearer $PAT_TOKEN"
ok "Patient token received"

# 3. /me
ME_STAFF=$(curl -s -w "\n%{http_code}" -H "$STAFF_HDR" "$BASE/me")
check_status "GET /me (staff)" "200" "$(echo "$ME_STAFF" | tail -n1)" "$(echo "$ME_STAFF" | sed '$d')"

# 4. Dashboard
DASH=$(curl -s -w "\n%{http_code}" -H "$STAFF_HDR" "$BASE/staff/dashboard/overview")
check_status "Staff dashboard" "200" "$(echo "$DASH" | tail -n1)" "$(echo "$DASH" | sed '$d')"

# 5. Priority patients
PRIORITY=$(curl -s -w "\n%{http_code}" -H "$STAFF_HDR" "$BASE/staff/patients/priority?per_page=5")
check_status "Priority patients" "200" "$(echo "$PRIORITY" | tail -n1)" "$(echo "$PRIORITY" | sed '$d')"

# 6. Patient profile
PROFILE=$(curl -s -w "\n%{http_code}" -H "$STAFF_HDR" "$BASE/patients/pat_001")
check_status "Patient detail" "200" "$(echo "$PROFILE" | tail -n1)" "$(echo "$PROFILE" | sed '$d')"

# 7. Medications & appointments
MEDS=$(curl -s -w "\n%{http_code}" -H "$STAFF_HDR" "$BASE/patients/pat_001/medications")
check_status "Medications" "200" "$(echo "$MEDS" | tail -n1)" "$(echo "$MEDS" | sed '$d')"
APPTS=$(curl -s -w "\n%{http_code}" -H "$STAFF_HDR" "$BASE/patients/pat_001/appointments")
check_status "Appointments" "200" "$(echo "$APPTS" | tail -n1)" "$(echo "$APPTS" | sed '$d')"

# 8. OCR upload → poll → confirm (dùng đơn thuốc mẫu thật)
OCR_FIXTURE="$(cd "$(dirname "$0")/../test/ocr" && pwd)/don_thuoc_chu_minh_tam.docx"
if [[ ! -f "$OCR_FIXTURE" ]]; then
  bad "Missing OCR fixture: $OCR_FIXTURE (chạy python scripts/generate_sample_prescription.py)"
fi
OCR_UP=$(curl -s -w "\n%{http_code}" -X POST "$BASE/patients/pat_001/documents" \
  -H "$STAFF_HDR" \
  -F "document_type=prescription" \
  -F "ocr_mode=auto" \
  -F "client_request_id=smoke-ocr-$(date +%s)" \
  -F "file=@${OCR_FIXTURE};type=application/vnd.openxmlformats-officedocument.wordprocessingml.document")
OCR_BODY=$(echo "$OCR_UP" | sed '$d')
OCR_CODE=$(echo "$OCR_UP" | tail -n1)
check_status "OCR upload" "202" "$OCR_CODE" "$OCR_BODY"
JOB_ID=$(echo "$OCR_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['job_id'])")
UPLOAD_ID=$(echo "$OCR_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['upload_id'])")

for i in $(seq 1 40); do
  OCR_JOB=$(curl -s -H "$STAFF_HDR" "$BASE/ocr/jobs/$JOB_ID")
  STATUS=$(echo "$OCR_JOB" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  if [[ "$STATUS" == "needs_review" ]]; then
    ok "OCR job polling → $STATUS"
    break
  fi
  if [[ "$STATUS" == "failed" ]]; then
    ERR=$(echo "$OCR_JOB" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('display_message') or d.get('error_message') or 'failed')")
    bad "OCR job failed: $ERR"
    break
  fi
  sleep 0.5
done
[[ "$STATUS" == "needs_review" ]] || bad "OCR job did not reach needs_review (last: $STATUS)"

CONFIRM=$(curl -s -w "\n%{http_code}" -X POST "$BASE/patients/pat_001/documents/$UPLOAD_ID/confirm_ocr" \
  -H "$STAFF_HDR" -H "Content-Type: application/json" \
  -d "{\"job_id\":\"$JOB_ID\",\"confirmed_by_user_id\":\"usr_demo_staff\",\"medications\":[{\"name\":\"Metformin\",\"strength\":\"500mg\",\"dosage\":\"1 vien\",\"frequency\":\"2 lan/ngay\",\"times_of_day\":[\"morning\",\"evening\"],\"instructions\":\"Uong sau an\",\"start_date\":\"2026-07-02\",\"end_date\":null}],\"follow_up\":null,\"nurse_note\":\"Smoke test\"}")
check_status "OCR confirm" "200" "$(echo "$CONFIRM" | tail -n1)" "$(echo "$CONFIRM" | sed '$d')"

# 9. Check-in today → submit → poll
TODAY=$(curl -s -w "\n%{http_code}" -H "$PAT_HDR" "$BASE/me/checkins/today")
TODAY_BODY=$(echo "$TODAY" | sed '$d')
check_status "Check-in today" "200" "$(echo "$TODAY" | tail -n1)" "$TODAY_BODY"
CHK_ID=$(echo "$TODAY_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['checkin']['id'])")

AUDIO=$(curl -s -w "\n%{http_code}" -H "$PAT_HDR" "$BASE/checkins/$CHK_ID/audio")
check_status "Check-in audio status" "200" "$(echo "$AUDIO" | tail -n1)" "$(echo "$AUDIO" | sed '$d')"

SUBMIT=$(curl -s -w "\n%{http_code}" -X POST "$BASE/checkins/$CHK_ID/responses" \
  -H "$PAT_HDR" \
  -F "quick_answer_id=normal" \
  -F "client_recorded_at=2026-07-05T08:00:00Z" \
  -F "client_request_id=smoke-checkin-$(date +%s)")
SUBMIT_BODY=$(echo "$SUBMIT" | sed '$d')
check_status "Check-in submit" "202" "$(echo "$SUBMIT" | tail -n1)" "$SUBMIT_BODY"
CHK_JOB=$(echo "$SUBMIT_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['job_id'])")

for i in $(seq 1 20); do
  CJ=$(curl -s -H "$PAT_HDR" "$BASE/checkin_jobs/$CHK_JOB")
  CSTATUS=$(echo "$CJ" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  if [[ "$CSTATUS" == "completed" ]]; then
    RISK=$(echo "$CJ" | python3 -c "import sys,json; print(json.load(sys.stdin)['risk']['level'])")
    ok "Check-in job → completed (risk=$RISK)"
    break
  fi
  sleep 0.2
done
[[ "$CSTATUS" == "completed" ]] || bad "Check-in job not completed (last: $CSTATUS)"

HIST=$(curl -s -w "\n%{http_code}" -H "$PAT_HDR" "$BASE/me/checkins/history?limit=5")
check_status "Check-in history" "200" "$(echo "$HIST" | tail -n1)" "$(echo "$HIST" | sed '$d')"

# 10. Hotline text
HOT_TEXT=$(curl -s -w "\n%{http_code}" -X POST "$BASE/hotline/questions" \
  -H "$PAT_HDR" -H "Content-Type: application/json" \
  -d '{"mode":"text","text":"Toi quen uong thuoc buoi sang thi co uong bu khong?","client_request_id":"smoke-hot-text-'$(date +%s)'"}')
check_status "Hotline text" "200" "$(echo "$HOT_TEXT" | tail -n1)" "$(echo "$HOT_TEXT" | sed '$d')"

# 11. Hotline voice (WAV mẫu thật cho STT production)
HOT_WAV="$(cd "$(dirname "$0")/../test/stt" && pwd)/STT.sample.wav"
if [[ ! -f "$HOT_WAV" ]]; then
  bad "Missing hotline audio fixture: $HOT_WAV"
fi
HOT_VOICE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/hotline/questions" \
  -H "$PAT_HDR" \
  -F "mode=voice" \
  -F "recorded_duration_seconds=3" \
  -F "client_request_id=smoke-hot-voice-$(date +%s)" \
  -F "audio_file=@${HOT_WAV};filename=voice.wav;type=audio/wav")
HOT_V_BODY=$(echo "$HOT_VOICE" | sed '$d')
HOT_V_CODE=$(echo "$HOT_VOICE" | tail -n1)
# mock mode may return 200 completed or 202 transcribing
if [[ "$HOT_V_CODE" == "200" || "$HOT_V_CODE" == "202" ]]; then
  ok "Hotline voice → HTTP $HOT_V_CODE"
else
  bad "Hotline voice → HTTP $HOT_V_CODE"
fi
HOT_QID=$(echo "$HOT_V_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['question_id'])")
for i in $(seq 1 40); do
  HQ=$(curl -s -H "$PAT_HDR" "$BASE/hotline/questions/$HOT_QID")
  HSTATUS=$(echo "$HQ" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  if [[ "$HSTATUS" == "completed" || "$HSTATUS" == "needs_review" ]]; then
    ok "Hotline voice poll → $HSTATUS"
    break
  fi
  if [[ "$HSTATUS" == "failed" ]]; then
    ERR=$(echo "$HQ" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('display_message') or d.get('error_message') or 'failed')")
    bad "Hotline voice failed: $ERR"
    break
  fi
  sleep 0.5
done
[[ "$HSTATUS" == "completed" || "$HSTATUS" == "needs_review" ]] || bad "Hotline voice not completed (last: $HSTATUS)"

HOT_HIST=$(curl -s -w "\n%{http_code}" -H "$PAT_HDR" "$BASE/hotline/questions?limit=5")
check_status "Hotline history" "200" "$(echo "$HOT_HIST" | tail -n1)" "$(echo "$HOT_HIST" | sed '$d')"

# 12. Timeline
TL=$(curl -s -w "\n%{http_code}" -H "$STAFF_HDR" "$BASE/staff/patients/pat_001/timeline?limit=10")
check_status "Patient timeline" "200" "$(echo "$TL" | tail -n1)" "$(echo "$TL" | sed '$d')"

# 13. Devices / notifications
DEV=$(curl -s -w "\n%{http_code}" -X POST "$BASE/devices/register" \
  -H "$PAT_HDR" -H "Content-Type: application/json" \
  -d '{"device_id":"smoke-ios","platform":"ios","notification_channel":"local","role":"patient","app_version":"1.0.0","os_version":"15.5","locale":"vi_VN"}')
check_status "Device register" "200" "$(echo "$DEV" | tail -n1)" "$(echo "$DEV" | sed '$d')"

PREF=$(curl -s -w "\n%{http_code}" -X PATCH "$BASE/devices/smoke-ios/notification_preferences" \
  -H "$PAT_HDR" -H "Content-Type: application/json" \
  -d '{"checkin_reminders_enabled":true,"medication_reminders_enabled":false,"appointment_reminders_enabled":true,"critical_staff_alerts_enabled":false}')
check_status "Notification preferences" "200" "$(echo "$PREF" | tail -n1)" "$(echo "$PREF" | sed '$d')"

# 14. Storage limits (26MB > default 25MB document cap)
BIG_FILE="/tmp/cv_smoke_big.pdf"
dd if=/dev/zero of="$BIG_FILE" bs=1024 count=26624 status=none 2>/dev/null
TOO_BIG=$(curl -s -w "\n%{http_code}" -X POST "$BASE/patients/pat_001/documents" \
  -H "$STAFF_HDR" \
  -F "document_type=prescription" \
  -F "ocr_mode=auto" \
  -F "client_request_id=smoke-too-big-$(date +%s)" \
  -F "file=@${BIG_FILE};filename=big.pdf;type=application/pdf")
rm -f "$BIG_FILE"
TB_CODE=$(echo "$TOO_BIG" | tail -n1)
if [[ "$TB_CODE" == "413" ]]; then
  ok "Storage limit → HTTP 413"
else
  bad "Storage limit expected 413, got $TB_CODE"
fi

BAD_TYPE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/patients/pat_001/documents" \
  -H "$STAFF_HDR" \
  -F "document_type=prescription" \
  -F "ocr_mode=auto" \
  -F "client_request_id=smoke-bad-type" \
  -F "file=@-;filename=notes.txt;type=text/plain" <<< "plain")
if [[ "$(echo "$BAD_TYPE" | tail -n1)" == "415" ]]; then
  ok "Unsupported media → HTTP 415"
else
  bad "Unsupported media expected 415"
fi

# 15. Error envelope
ERR=$(curl -s -w "\n%{http_code}" "$BASE/me")
ERR_BODY=$(echo "$ERR" | sed '$d')
check_status "Unauthorized /me" "401" "$(echo "$ERR" | tail -n1)" "$ERR_BODY"
echo "$ERR_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['error']['code']=='unauthorized'; assert d['error']['trace_id'].startswith('req_')"
ok "Error envelope format"

echo
echo "=== Kết quả: $PASS passed, $FAIL failed ==="