#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE_URL:-http://127.0.0.1:8000/api/v1}"
OCR_DIR="$(cd "$(dirname "$0")/../test/ocr" && pwd)"
PASS=0
FAIL=0

ok() { echo "✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "❌ $1"; FAIL=$((FAIL + 1)); }

echo "=== CareVoice production OCR test ==="
echo "API: $BASE"
echo

STAFF_LOGIN=$(curl -s -w "\n%{http_code}" -X POST "$BASE/auth/staff/login" \
  -H "Content-Type: application/json" \
  -d '{"login":"nurse","password":"nurse","device_id":"prod-ocr-test"}')
STAFF_CODE=$(echo "$STAFF_LOGIN" | tail -n1)
STAFF_BODY=$(echo "$STAFF_LOGIN" | sed '$d')
if [[ "$STAFF_CODE" != "200" ]]; then
  bad "Staff login failed (HTTP $STAFF_CODE)"
  echo "$STAFF_BODY"
  exit 1
fi
STAFF_TOKEN=$(echo "$STAFF_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
STAFF_HDR="Authorization: Bearer $STAFF_TOKEN"
ok "Staff login"

PATIENT_ID=$(curl -s -H "$STAFF_HDR" "$BASE/staff/patients/priority?per_page=1" | python3 -c "import sys,json; print(json.load(sys.stdin)['items'][0]['patient_id'])")
ok "Using patient $PATIENT_ID"

shopt -s nullglob
DOCX_FILES=("$OCR_DIR"/don_thuoc_*.docx)
if [[ ${#DOCX_FILES[@]} -eq 0 ]]; then
  bad "No prescription fixtures in $OCR_DIR"
  exit 1
fi

for docx in "${DOCX_FILES[@]}"; do
  name=$(basename "$docx")
  req_id="prod-ocr-${name}-$(date +%s)"
  upload=$(curl -s -w "\n%{http_code}" -X POST "$BASE/patients/$PATIENT_ID/documents" \
    -H "$STAFF_HDR" \
    -F "document_type=prescription" \
    -F "ocr_mode=auto" \
    -F "client_request_id=$req_id" \
    -F "file=@${docx};type=application/vnd.openxmlformats-officedocument.wordprocessingml.document")
  code=$(echo "$upload" | tail -n1)
  body=$(echo "$upload" | sed '$d')
  if [[ "$code" != "202" ]]; then
    bad "$name upload → HTTP $code"
    echo "$body"
    continue
  fi
  job_id=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin)['job_id'])")

  status="queued"
  patient_name=""
  med_count=0
  for _ in $(seq 1 40); do
    job=$(curl -s -H "$STAFF_HDR" "$BASE/ocr/jobs/$job_id")
    status=$(echo "$job" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
    if [[ "$status" == "needs_review" ]]; then
      patient_name=$(echo "$job" | python3 -c "import sys,json; d=json.load(sys.stdin); print((d.get('draft_patient') or {}).get('full_name','?'))")
      med_count=$(echo "$job" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('draft_medications') or []))")
      ok "$name → $status ($patient_name, $med_count thuốc)"
      break
    fi
    if [[ "$status" == "failed" ]]; then
      err=$(echo "$job" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('display_message') or d.get('error_message') or 'failed')")
      bad "$name → failed: $err"
      break
    fi
    sleep 0.5
  done
  if [[ "$status" != "needs_review" && "$status" != "failed" ]]; then
    bad "$name → timeout (last status: $status)"
  fi
done

echo
echo "=== Kết quả: $PASS passed, $FAIL failed / ${#DOCX_FILES[@]} files ==="
[[ "$FAIL" -eq 0 ]]