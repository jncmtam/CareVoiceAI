// ĐÃ KHỚP BACKEND DEMO — production cần thay mock VNPT bằng gateway thật

# Hợp đồng REST API CareVoice AI

Tài liệu này mô tả contract cho iOS app. Backend Python/FastAPI là lớp trung gian duy nhất app gọi vào. App không gọi trực tiếp VNPT để tránh lộ token; OCR/STT/TTS/tóm tắt/phân loại nguy cơ đều nằm ở backend.

## Quy ước chung

- Base URL demo: `https://api.carevoice.local/api/v1`
- Auth: `Authorization: Bearer <jwt>`
- Content type mặc định: `application/json; charset=utf-8`
- Upload file: `multipart/form-data`
- Thời gian: ISO 8601, UTC từ server, ví dụ `2026-07-01T02:30:00Z`
- Field JSON: `snake_case`
- ID: UUID string, trừ khi backend SQLite demo chọn integer nội bộ nhưng vẫn nên expose string.
- Idempotency cho upload/gửi ghi âm: client gửi `client_request_id` để backend tránh double-submit.
- Mức nguy cơ chuẩn:
  - `normal`: bình thường
  - `attention`: cần chú ý
  - `intervention`: cần can thiệp
- Trạng thái job chuẩn:
  - `queued`, `uploading`, `processing`, `transcribing`, `analyzing`, `summarizing`, `needs_review`, `completed`, `failed`, `cancelled`, `expired`
- Phản hồi lỗi chuẩn:

```json
{
  "error": {
    "code": "job_timeout",
    "message": "Hệ thống xử lý quá lâu. Vui lòng thử lại sau.",
    "details": {},
    "trace_id": "req_01H..."
  }
}
```

Mã lỗi dự kiến: `400 invalid_request`, `401 unauthorized`, `403 forbidden`, `404 not_found`, `409 conflict`, `413 file_too_large`, `415 unsupported_media_type`, `422 validation_error`, `429 rate_limited`, `500 internal_error`, `503 vendor_unavailable`, `504 job_timeout`.

## Giới Hạn Upload Và Background Jobs

Backend kiểm tra kích thước theo `Content-Type` khi stream file vào `storage/` local (hoặc object storage sau này):

| Loại file | MIME gợi ý | Giới hạn mặc định | Env |
| --- | --- | --- | --- |
| Đơn thuốc/PDF/ảnh | `application/pdf`, `image/jpeg`, `image/png`, `image/heic` | 25 MB | `MAX_DOCUMENT_UPLOAD_BYTES` |
| Ghi âm check-in/hotline | `audio/m4a`, `audio/mp4`, `audio/mpeg`, `audio/wav`, ... | 250 MB | `MAX_AUDIO_UPLOAD_BYTES` |
| Media sinh ra (TTS) | backend ghi nội bộ | 50 MB | `MAX_GENERATED_MEDIA_BYTES` |
| Fallback khác | mọi type còn lại | 10 MB | `MAX_UPLOAD_BYTES` |

Khi `VENDOR_MOCK_MODE=false`, OCR/check-in/hotline voice trả `202` ngay và xử lý nền qua `job_runner` (delay ngắn sau `commit` request). App vẫn polling `GET /ocr/jobs/{job_id}`, `GET /checkin_jobs/{job_id}` hoặc `GET /hotline/questions/{question_id}` như contract cũ.

## Xác Thực

### POST `/auth/staff/login`

Đăng nhập điều dưỡng/bác sĩ bằng email hoặc mã nhân viên + mật khẩu.

Yêu cầu:

```json
{
  "login": "nurse01@hospital.vn",
  "password": "secret",
  "device_id": "ios-device-uuid"
}
```

Phản hồi `200`:

```json
{
  "access_token": "jwt",
  "refresh_token": "refresh_jwt",
  "token_type": "bearer",
  "expires_in": 3600,
  "user": {
    "id": "usr_001",
    "role": "nurse",
    "full_name": "Nguyễn Thị Lan",
    "staff_code": "DD001",
    "department": "Nội tiết"
  }
}
```

Trạng thái đặc biệt: sync. Lỗi `401 unauthorized`, `403 forbidden`.

### POST `/auth/patient/request_otp`

Xin OTP cho bệnh nhân/người nhà bằng số điện thoại, có thể kèm mã bệnh nhân.

Yêu cầu:

```json
{
  "phone_number": "+84901234567",
  "patient_code": "BN-2026-0001"
}
```

Phản hồi `200`:

```json
{
  "otp_session_id": "otp_123",
  "masked_phone_number": "+84******567",
  "expires_in": 300,
  "can_resend_after": 60
}
```

Trạng thái đặc biệt: sync. Lỗi `404 not_found`, `429 rate_limited`.

### POST `/auth/patient/verify_otp`

Xác thực OTP và trả token cho vai trò `patient` hoặc `caregiver`.

Yêu cầu:

```json
{
  "otp_session_id": "otp_123",
  "otp_code": "123456",
  "device_id": "ios-device-uuid"
}
```

Phản hồi `200`:

```json
{
  "access_token": "jwt",
  "refresh_token": "refresh_jwt",
  "token_type": "bearer",
  "expires_in": 3600,
  "user": {
    "id": "usr_patient_001",
    "role": "patient",
    "full_name": "Trần Văn Bình"
  },
  "patient": {
    "id": "pat_001",
    "patient_code": "BN-2026-0001",
    "full_name": "Trần Văn Bình"
  }
}
```

Trạng thái đặc biệt: sync. Lỗi `401 unauthorized`, `410 otp_expired`.

### POST `/auth/patient/login_code`

Đăng nhập đơn giản bằng mã bệnh nhân được cấp sẵn. Dùng cho demo hoặc cơ sở không triển khai OTP.

Yêu cầu:

```json
{
  "patient_code": "BN-2026-0001",
  "phone_last4": "4567",
  "device_id": "ios-device-uuid"
}
```

Phản hồi `200`: giống `/auth/patient/verify_otp`.

Trạng thái đặc biệt: sync. Lỗi `401 unauthorized`, `404 not_found`.

### POST `/auth/refresh`

Yêu cầu:

```json
{
  "refresh_token": "refresh_jwt"
}
```

Phản hồi `200`:

```json
{
  "access_token": "new_jwt",
  "refresh_token": "new_refresh_jwt",
  "token_type": "bearer",
  "expires_in": 3600
}
```

Trạng thái đặc biệt: sync. Lỗi `401 unauthorized`.

### POST `/auth/logout`

Yêu cầu:

```json
{
  "device_id": "ios-device-uuid",
  "refresh_token": "refresh_jwt"
}
```

Phản hồi `204`: không body.

### GET `/me`

Lấy profile người dùng hiện tại và role để app restore session.

Phản hồi `200`:

```json
{
  "user": {
    "id": "usr_001",
    "role": "nurse",
    "full_name": "Nguyễn Thị Lan"
  },
  "patient": null
}
```

## Hồ Sơ Bệnh Nhân Và OCR

### POST `/patients`

Tạo bệnh nhân mới. Chỉ staff được gọi.

Yêu cầu:

```json
{
  "patient_code": "BN-2026-0001",
  "full_name": "Trần Văn Bình",
  "date_of_birth": "1958-03-20",
  "gender": "male",
  "phone_number": "+84901234567",
  "caregiver_name": "Trần Minh Anh",
  "caregiver_phone_number": "+84987654321",
  "diagnoses": ["type_2_diabetes", "hypertension"],
  "address": "Quận 3, TP.HCM",
  "primary_doctor_name": "BS. Lê Minh",
  "notes": "Nghe kém, ưu tiên gọi cho người nhà sau 19:00."
}
```

Phản hồi `201`:

```json
{
  "patient": {
    "id": "pat_001",
    "patient_code": "BN-2026-0001",
    "full_name": "Trần Văn Bình",
    "age": 68,
    "latest_risk_level": "normal",
    "is_active": true
  }
}
```

Trạng thái đặc biệt: sync. Lỗi `409 conflict` nếu trùng mã bệnh nhân.

### GET `/patients/{patient_id}`

Lấy chi tiết hồ sơ bệnh nhân. Nhân viên xem được bệnh nhân thuộc phạm vi phụ trách; bệnh nhân chỉ xem chính mình qua `/me/patient`.

Phản hồi `200`:

```json
{
  "patient": {
    "id": "pat_001",
    "patient_code": "BN-2026-0001",
    "full_name": "Trần Văn Bình",
    "date_of_birth": "1958-03-20",
    "gender": "male",
    "phone_number": "+84901234567",
    "caregiver_name": "Trần Minh Anh",
    "caregiver_phone_number": "+84987654321",
    "diagnoses": ["type_2_diabetes", "hypertension"],
    "latest_risk_level": "attention",
    "latest_checkin_at": "2026-07-01T01:15:00Z",
    "next_appointment_at": "2026-07-14T02:00:00Z",
    "notes": "Nghe kém."
  }
}
```

### PATCH `/patients/{patient_id}`

Cập nhật hồ sơ. Chỉ staff.

Yêu cầu:

```json
{
  "phone_number": "+84901234567",
  "caregiver_phone_number": "+84987654321",
  "notes": "Cập nhật số người nhà."
}
```

Phản hồi `200`: trả `patient` sau cập nhật.

### GET `/me/patient`

Bệnh nhân/người nhà lấy hồ sơ chính mình.

Phản hồi `200`: giống phần `patient` của `/patients/{patient_id}` nhưng không trả ghi chú nội bộ nhạy cảm.

### POST `/patients/{patient_id}/documents`

Upload ảnh/PDF đơn thuốc hoặc giấy xuất viện. API trả ngay `job_id`, không chờ OCR xong. Backend upload VNPT `addFile`, gọi `ocr/scan` hoặc async `scan-table`, rồi cập nhật job.

Yêu cầu `multipart/form-data`:

- `document_type`: `prescription` hoặc `discharge_note`
- `ocr_mode`: `auto`, `basic`, `table`
- `file`: ảnh/PDF
- `client_request_id`: UUID do app sinh

Phản hồi `202`:

```json
{
  "upload_id": "upl_001",
  "job_id": "ocr_job_001",
  "status": "queued",
  "poll_after_seconds": 2,
  "message": "Hệ thống đang đọc đơn thuốc. Điều dưỡng có thể quay lại sau."
}
```

Trạng thái đặc biệt: async, cần polling `GET /ocr/jobs/{job_id}`. Lỗi `413 file_too_large`, `415 unsupported_media_type`, `503 vendor_unavailable`.

### GET `/ocr/jobs/{job_id}`

Lấy trạng thái và kết quả OCR tạm. App dùng polling exponential backoff, timeout UI đề xuất 90 giây nhưng job vẫn tiếp tục ở backend.

Phản hồi `200` khi đang xử lý:

```json
{
  "job_id": "ocr_job_001",
  "upload_id": "upl_001",
  "patient_id": "pat_001",
  "status": "processing",
  "progress": 45,
  "stage": "ocr_table_polling",
  "poll_after_seconds": 3,
  "created_at": "2026-07-01T02:00:00Z",
  "updated_at": "2026-07-01T02:00:07Z"
}
```

Phản hồi `200` khi cần điều dưỡng xác nhận:

```json
{
  "job_id": "ocr_job_001",
  "upload_id": "upl_001",
  "patient_id": "pat_001",
  "status": "needs_review",
  "progress": 100,
  "raw_text": "Metformin 500mg...",
  "draft_medications": [
    {
      "name": "Metformin",
      "strength": "500mg",
      "dosage": "1 viên",
      "frequency": "2 lần/ngày",
      "times_of_day": ["morning", "evening"],
      "instructions": "Uống sau ăn",
      "confidence": 0.88
    }
  ],
  "draft_follow_up": {
    "appointment_at": "2026-07-14T02:00:00Z",
    "department": "Nội tiết"
  },
  "warnings": [
    "Có 1 dòng thuốc độ tin cậy thấp, cần kiểm tra lại."
  ],
  "poll_after_seconds": null
}
```

Trạng thái đặc biệt: polling. `needs_review` là kết quả thành công nhưng chưa lưu chính thức vào hồ sơ.

### POST `/ocr/jobs/{job_id}/cancel`

Huỷ job OCR nếu điều dưỡng rời luồng hoặc upload nhầm. Backend gọi VNPT cancel nếu job đang ở async session.

Yêu cầu:

```json
{
  "reason": "uploaded_wrong_file"
}
```

Phản hồi `200`:

```json
{
  "job_id": "ocr_job_001",
  "status": "cancelled"
}
```

### POST `/patients/{patient_id}/documents/{upload_id}/confirm_ocr`

Điều dưỡng xác nhận/sửa OCR trước khi lưu chính thức vào hồ sơ. Đây là human-in-the-loop bắt buộc.

Yêu cầu:

```json
{
  "job_id": "ocr_job_001",
  "confirmed_by_user_id": "usr_001",
  "medications": [
    {
      "name": "Metformin",
      "strength": "500mg",
      "dosage": "1 viên",
      "frequency": "2 lần/ngày",
      "times_of_day": ["morning", "evening"],
      "instructions": "Uống sau ăn",
      "start_date": "2026-07-01",
      "end_date": null
    }
  ],
  "follow_up": {
    "appointment_at": "2026-07-14T02:00:00Z",
    "department": "Nội tiết",
    "doctor_name": "BS. Lê Minh"
  },
  "nurse_note": "Đã đối chiếu với ảnh đơn thuốc."
}
```

Phản hồi `200`:

```json
{
  "document": {
    "id": "doc_001",
    "document_type": "prescription",
    "status": "confirmed",
    "confirmed_at": "2026-07-01T02:04:00Z"
  },
  "medications": [
    {
      "id": "med_001",
      "name": "Metformin",
      "strength": "500mg",
      "dosage": "1 viên",
      "frequency": "2 lần/ngày",
      "times_of_day": ["morning", "evening"],
      "instructions": "Uống sau ăn"
    }
  ]
}
```

Trạng thái đặc biệt: sync. Lỗi `409 conflict` nếu job chưa `needs_review` hoặc đã xác nhận.

### GET `/patients/{patient_id}/medications`

Nhân viên xem thuốc của bệnh nhân; app bệnh nhân dùng `/me/medications`.

Phản hồi `200`:

```json
{
  "medications": [
    {
      "id": "med_001",
      "name": "Metformin",
      "strength": "500mg",
      "dosage": "1 viên",
      "frequency": "2 lần/ngày",
      "times_of_day": ["morning", "evening"],
      "instructions": "Uống sau ăn",
      "is_active": true
    }
  ]
}
```

### GET `/me/medications`

Bệnh nhân/người nhà xem đơn thuốc đã được điều dưỡng xác nhận.

Phản hồi `200`: giống `/patients/{patient_id}/medications`.

### GET `/patients/{patient_id}/appointments`

Phản hồi `200`:

```json
{
  "appointments": [
    {
      "id": "appt_001",
      "appointment_at": "2026-07-14T02:00:00Z",
      "department": "Nội tiết",
      "doctor_name": "BS. Lê Minh",
      "status": "scheduled"
    }
  ]
}
```

### GET `/me/appointments`

Bệnh nhân/người nhà xem lịch tái khám.

Phản hồi `200`: giống `/patients/{patient_id}/appointments`.

## Check-In Và Xử Lý Giọng Nói

### GET `/me/checkins/today`

Lấy câu hỏi hôm nay và audio TTS đã chuẩn bị sẵn nếu có. Backend nên pre-generate audio khi lên lịch check-in.

Phản hồi `200`:

```json
{
  "checkin": {
    "id": "chk_001",
    "patient_id": "pat_001",
    "scheduled_for": "2026-07-01",
    "status": "ready",
    "question_text": "Hôm nay bác có thấy mệt, khó thở hoặc đau ngực không?",
    "audio_status": "ready",
    "audio_url": "https://api.carevoice.local/media/tts/chk_001.m4a",
    "audio_cache_key": "tts_chk_001_v1",
    "quick_answers": [
      {"id": "yes", "label": "Có"},
      {"id": "no", "label": "Không"},
      {"id": "normal", "label": "Bình thường"}
    ],
    "expires_at": "2026-07-01T16:59:59Z"
  }
}
```

Phản hồi `200` nếu TTS chưa sẵn:

```json
{
  "checkin": {
    "id": "chk_001",
    "status": "preparing_audio",
    "question_text": "Hôm nay bác có thấy mệt, khó thở hoặc đau ngực không?",
    "audio_status": "generating",
    "audio_url": null,
    "tts_job_id": "tts_job_001",
    "poll_after_seconds": 2,
    "quick_answers": []
  }
}
```

Trạng thái đặc biệt: sync nếu audio sẵn; nếu `audio_status = generating`, app polling `GET /checkins/{checkin_id}/audio`.

### GET `/checkins/{checkin_id}/audio`

Polling trạng thái audio TTS do backend wrap VNPT `check-status`.

Phản hồi `200`:

```json
{
  "checkin_id": "chk_001",
  "audio_status": "ready",
  "audio_url": "https://api.carevoice.local/media/tts/chk_001.m4a",
  "audio_cache_key": "tts_chk_001_v1",
  "poll_after_seconds": null
}
```

Trạng thái đặc biệt: polling nhẹ. App hiển thị ngôn ngữ đời thường: "Đang chuẩn bị câu hỏi...".

### POST `/checkins/{checkin_id}/transcribe`

Xem trước chữ từ ghi âm (không tạo alert). App dùng trước bước gửi chính thức.

Yêu cầu `multipart/form-data`:

- `audio_file`: file ghi âm
- `recorded_duration_seconds`: optional

Phản hồi `200`:

```json
{
  "transcript": "Hôm nay tôi hơi chóng mặt sau khi uống thuốc.",
  "suggested_risk_level": "attention",
  "message": "Bác có thể chỉnh lại chữ trước khi gửi."
}
```

### POST `/checkins/{checkin_id}/responses`

Gửi câu trả lời check-in. Backend tự quyết định STT sync/async theo thời lượng file, sau đó phân loại nguy cơ và tóm tắt. API trả ngay `job_id`.

Yêu cầu `multipart/form-data`:

- `audio_file`: file `.m4a`/`.wav`, optional nếu chỉ gửi quick answer
- `quick_answer_id`: `yes`, `no`, `normal`, optional
- `confirmed_transcript`: chữ BN xác nhận, optional
- `patient_declared_risk_level`: `normal`, `attention`, `intervention`, optional (bắt buộc nếu có `confirmed_transcript`)
- `recorded_duration_seconds`: số giây, optional
- `client_recorded_at`: ISO 8601
- `client_request_id`: UUID

Phản hồi `202`:

```json
{
  "response_id": "resp_001",
  "job_id": "checkin_job_001",
  "status": "queued",
  "poll_after_seconds": 2,
  "message": "Đã nhận câu trả lời. Hệ thống đang gửi điều dưỡng xem lại nếu cần."
}
```

Trạng thái đặc biệt: async, cần polling `GET /checkin_jobs/{job_id}`. Nếu mất mạng, app lưu file local và retry sau.

### GET `/checkin_jobs/{job_id}`

Polling kết quả STT -> phân loại -> tóm tắt.

Phản hồi `200` khi đang chạy:

```json
{
  "job_id": "checkin_job_001",
  "response_id": "resp_001",
  "status": "analyzing",
  "progress": 70,
  "stage": "risk_classification",
  "display_message": "Đang phân tích phản hồi...",
  "poll_after_seconds": 3
}
```

Phản hồi `200` khi hoàn tất:

```json
{
  "job_id": "checkin_job_001",
  "response_id": "resp_001",
  "status": "completed",
  "transcript": "Hôm nay tôi hơi chóng mặt sau khi uống thuốc.",
  "summary": "Bệnh nhân báo chóng mặt sau uống thuốc, chưa ghi nhận đau ngực hoặc khó thở.",
  "risk": {
    "level": "attention",
    "label": "Cần chú ý",
    "reasons": ["Có triệu chứng chóng mặt sau dùng thuốc"],
    "analysis_hints": ["Nội dung: đề cập đau/nhức"],
    "needs_staff_review": true
  },
  "staff_alert_id": "alert_001",
  "completed_at": "2026-07-01T02:20:00Z"
}
```

Trạng thái đặc biệt: polling. App tuyệt đối không diễn đạt là AI chẩn đoán; chỉ hiển thị "Hệ thống gợi ý, điều dưỡng sẽ xác nhận nếu cần."

### GET `/me/checkins/history`

Lịch sử check-in đơn giản cho bệnh nhân.

Query: `limit`, `cursor`

Phản hồi `200`:

```json
{
  "items": [
    {
      "id": "resp_001",
      "checked_in_at": "2026-07-01T02:20:00Z",
      "status": "reviewed",
      "risk_level": "attention",
      "patient_message": "Điều dưỡng đã xem",
      "summary_for_patient": "Bác đã gửi phản hồi hôm nay."
    }
  ],
  "next_cursor": null
}
```

## Bảng Điều Khiển Điều Dưỡng/Bác Sĩ

### GET `/staff/dashboard/overview`

KPI đầu dashboard.

Phản hồi `200`:

```json
{
  "total_active_patients": 128,
  "needs_attention_today": 14,
  "needs_intervention_today": 3,
  "checkin_completion_rate": 0.76,
  "pending_ocr_jobs": 2,
  "pending_analysis_jobs": 5,
  "updated_at": "2026-07-01T02:30:00Z"
}
```

### GET `/staff/patients/priority`

Danh sách bệnh nhân đã sort theo ưu tiên: `intervention` trước, rồi `attention`, rồi `normal`; trong cùng nhóm sort theo thời gian mới nhất.

Query:

- `risk_level`: optional `normal|attention|intervention`
- `handling_status`: optional `new|viewed|called_back|resolved`
- `actionable_only`: optional `true` — chỉ BN có alert mở (`new`/`viewed`/`called_back`) hoặc risk ≥ attention
- `query`: tên/SĐT/mã bệnh nhân
- `page`: mặc định `1`
- `per_page`: mặc định `30`, tối đa `100`

Phản hồi `200`:

```json
{
  "items": [
    {
      "patient_id": "pat_001",
      "patient_code": "BN-2026-0001",
      "full_name": "Trần Văn Bình",
      "age": 68,
      "diagnoses": ["type_2_diabetes", "hypertension"],
      "latest_risk_level": "intervention",
      "latest_summary": "Báo đau ngực và khó thở nhẹ.",
      "latest_checkin_at": "2026-07-01T02:20:00Z",
      "handling_status": "new",
      "unread_alert_count": 1
    }
  ],
  "page": 1,
  "per_page": 30,
  "total": 128,
  "has_next": true
}
```

### GET `/staff/patients/{patient_id}/timeline`

Timeline chi tiết. Bao gồm cả entry đang xử lý để UI hiện "Đang phân tích..." thay vì trống.

Query: `limit`, `cursor`

Phản hồi `200`:

```json
{
  "patient": {
    "id": "pat_001",
    "patient_code": "BN-2026-0001",
    "full_name": "Trần Văn Bình",
    "age": 68,
    "latest_risk_level": "attention"
  },
  "items": [
    {
      "id": "tl_001",
      "type": "checkin_response",
      "occurred_at": "2026-07-01T02:20:00Z",
      "status": "completed",
      "risk_level": "attention",
      "summary": "Bệnh nhân báo chóng mặt sau uống thuốc.",
      "transcript": "Hôm nay tôi hơi chóng mặt sau khi uống thuốc.",
      "risk_reasons": ["Có triệu chứng chóng mặt sau dùng thuốc"],
      "handling_status": "new",
      "staff_alert_id": "alert_001",
      "audio_url": "https://api.carevoice.local/media/pat_001/checkins/chk_001/answer.m4a",
      "quick_answer_id": "yes",
      "patient_declared_risk_level": "attention",
      "recorded_duration_seconds": 12,
      "analysis_hints": ["Nội dung: đề cập đau/nhức"]
    },
    {
      "id": "tl_002",
      "type": "checkin_response",
      "occurred_at": "2026-07-01T03:00:00Z",
      "status": "analyzing",
      "risk_level": null,
      "summary": null,
      "display_message": "Đang phân tích phản hồi...",
      "job_id": "checkin_job_002"
    }
  ],
  "next_cursor": null
}
```

### PATCH `/staff/patients/{patient_id}/timeline/{entry_id}/handling`

Cập nhật trạng thái xử lý: đã xem, đã gọi lại, ghi chú.

Yêu cầu:

```json
{
  "handling_status": "called_back",
  "note": "Đã gọi lại, dặn theo dõi huyết áp và tái khám nếu chóng mặt tăng.",
  "callback_at": "2026-07-01T02:45:00Z"
}
```

Phản hồi `200`:

```json
{
  "entry_id": "tl_001",
  "handling_status": "called_back",
  "handled_by": {
    "id": "usr_001",
    "full_name": "Nguyễn Thị Lan"
  },
  "handled_at": "2026-07-01T02:46:00Z",
  "note": "Đã gọi lại, dặn theo dõi huyết áp và tái khám nếu chóng mặt tăng."
}
```

Trạng thái đặc biệt: sync. Lỗi `409 conflict` nếu entry đang `analyzing`.

## Hỏi Đáp Hotline

### POST `/hotline/questions`

Gửi câu hỏi tự do bằng text hoặc voice. Backend chỉ trả lời trong phạm vi hồ sơ/hướng dẫn đã xác nhận; nếu ngoài phạm vi hoặc có dấu hiệu nguy hiểm, trả `needs_staff_review = true`.

Yêu cầu JSON cho text:

```json
{
  "mode": "text",
  "patient_id": "pat_001",
  "text": "Tôi quên uống thuốc buổi sáng thì có uống bù không?",
  "client_request_id": "uuid"
}
```

Yêu cầu `multipart/form-data` cho giọng nói:

- `mode`: `voice`
- `patient_id`: optional với patient role, required nếu staff hỏi thay
- `audio_file`: file `.m4a`/`.wav`
- `recorded_duration_seconds`
- `client_request_id`

Phản hồi `200` nếu xử lý ngay:

```json
{
  "question_id": "hot_001",
  "status": "completed",
  "transcript": "Tôi quên uống thuốc buổi sáng thì có uống bù không?",
  "answer_text": "Bác không tự ý uống bù. Bác vui lòng liên hệ điều dưỡng để được hướng dẫn theo đơn hiện tại.",
  "source_scope": "confirmed_medical_record",
  "needs_staff_review": true,
  "risk_level": "attention",
  "reasons": ["Câu hỏi liên quan hướng dẫn dùng thuốc cần nhân viên y tế xác nhận."],
  "staff_alert_id": "alert_002"
}
```

Phản hồi `202` nếu giọng nói cần STT/tóm tắt:

```json
{
  "question_id": "hot_002",
  "job_id": "hotline_job_001",
  "status": "transcribing",
  "poll_after_seconds": 2
}
```

Trạng thái đặc biệt: có thể sync hoặc async. App polling `GET /hotline/questions/{question_id}` khi có `job_id`.

### GET `/hotline/questions/{question_id}`

Phản hồi `200`:

```json
{
  "question_id": "hot_002",
  "status": "completed",
  "transcript": "Tôi thấy đau ngực thì có nên uống thuốc không?",
  "answer_text": "Triệu chứng này cần điều dưỡng/bác sĩ xem lại. Hệ thống đã gửi cảnh báo.",
  "needs_staff_review": true,
  "risk_level": "intervention",
  "reasons": ["Hotline: bệnh nhân báo đau ngực"],
  "staff_alert_id": "alert_003",
  "poll_after_seconds": null
}
```

### GET `/hotline/questions`

Lịch sử hotline của bệnh nhân hiện tại hoặc bệnh nhân do staff chọn.

Query: `patient_id`, `limit`, `cursor`

Phản hồi `200`:

```json
{
  "items": [
    {
      "question_id": "hot_001",
      "asked_at": "2026-07-01T02:50:00Z",
      "mode": "text",
      "question_text": "Tôi quên uống thuốc buổi sáng thì có uống bù không?",
      "transcript": "Tôi quên uống thuốc buổi sáng thì có uống bù không?",
      "answer_text": "Bác không tự ý uống bù...",
      "needs_staff_review": true,
      "risk_level": "attention",
      "reasons": ["Câu hỏi liên quan hướng dẫn dùng thuốc cần nhân viên y tế xác nhận."]
    }
  ],
  "next_cursor": null
}
```

## Thông Báo Không Cần Apple Developer

### POST `/devices/register`

Đăng ký thiết bị và kênh thông báo. Mặc định dùng `notification_channel = "local"` để app iOS tự đặt local notification, không cần Apple Developer Program. Nếu sau này có Apple Developer, client có thể gửi `notification_channel = "apns"` kèm `device_token`. Nếu cần server push miễn phí thật sự, triển khai PWA dùng `web_push`; kênh này dành cho web app cài lên Home Screen, không phải native iOS app.

Yêu cầu local notification:

```json
{
  "device_id": "ios-device-uuid",
  "platform": "ios",
  "notification_channel": "local",
  "role": "patient",
  "app_version": "1.0.0",
  "os_version": "15.5.2",
  "locale": "vi_VN"
}
```

Yêu cầu APNs sau MVP:

```json
{
  "device_id": "ios-device-uuid",
  "device_token": "apns-token",
  "platform": "ios",
  "notification_channel": "apns",
  "push_environment": "sandbox",
  "role": "patient",
  "app_version": "1.0.0",
  "os_version": "15.5.2",
  "locale": "vi_VN"
}
```

Phản hồi `200`:

```json
{
  "device_id": "ios-device-uuid",
  "registered": true,
  "notification_channel": "local",
  "remote_push_enabled": false,
  "message": "Đã đăng ký thiết bị cho local notification. Không cần Apple Developer Program.",
  "updated_at": "2026-07-01T02:55:00Z"
}
```

### DELETE `/devices/{device_id}`

Gỡ đăng ký thiết bị khi logout hoặc user tắt thông báo.

Phản hồi `204`: không body.

### GET `/devices/{device_id}/notification_preferences`

Lấy tuỳ chọn thông báo đã lưu. Nếu thiết bị chưa có record, backend trả bộ mặc định.

Phản hồi `200`:

```json
{
  "device_id": "ios-device-uuid",
  "preferences": {
    "checkin_reminders_enabled": true,
    "medication_reminders_enabled": true,
    "appointment_reminders_enabled": true,
    "critical_staff_alerts_enabled": true
  }
}
```

### PATCH `/devices/{device_id}/notification_preferences`

Tuỳ chọn thông báo.

Yêu cầu:

```json
{
  "checkin_reminders_enabled": true,
  "medication_reminders_enabled": true,
  "appointment_reminders_enabled": true,
  "critical_staff_alerts_enabled": true
}
```

Phản hồi `200`:

```json
{
  "device_id": "ios-device-uuid",
  "preferences": {
    "checkin_reminders_enabled": true,
    "medication_reminders_enabled": true,
    "appointment_reminders_enabled": true,
    "critical_staff_alerts_enabled": true
  }
}
```

## eKYC Sau MVP

### POST `/identity/face_verification/sessions`

Tạo phiên xác thực khuôn mặt khi tái khám. Đây là phần tạm thời vì chưa có field VNPT eKYC chi tiết.

Yêu cầu:

```json
{
  "patient_id": "pat_001",
  "purpose": "follow_up_visit"
}
```

Phản hồi `201`:

```json
{
  "session_id": "face_001",
  "status": "not_started",
  "upload_url": "https://api.carevoice.local/identity/face_verification/sessions/face_001/upload",
  "expires_at": "2026-07-01T03:30:00Z"
}
```

### GET `/identity/face_verification/sessions/{session_id}`

Phản hồi `200`:

```json
{
  "session_id": "face_001",
  "status": "verified",
  "verified_at": "2026-07-01T03:10:00Z",
  "needs_staff_review": false
}
```

## Ánh Xạ Backend Với VNPT

| API CareVoice | VNPT phía sau | Tác động lên UI |
| --- | --- | --- |
| `POST /patients/{id}/documents` | `file-service/v1/addFile` + `ocr/scan` hoặc async `integration/ocr/scan-table` | Trả `job_id` ngay, app hiện `PollingStatusView`, cho rời màn hình. |
| `GET /ocr/jobs/{job_id}` | `scan-table/result` hoặc kết quả OCR đã cache | Polling cho tới `needs_review`, `failed`, `cancelled`. |
| `GET /me/checkins/today` | Lịch đã cache + TTS đã cache | Nếu audio chưa sẵn, trả `audio_status = generating`. |
| `GET /checkins/{id}/audio` | `tts-service/v1/check-status` | Polling ngầm, bệnh nhân chỉ thấy "Đang chuẩn bị...". |
| `POST /checkins/{id}/responses` | VNPT STT sync hoặc async, backend tự chọn | App không chọn route VNPT; chỉ upload và nhận `job_id`. |
| `GET /checkin_jobs/{job_id}` | Kết quả STT + phân loại risk + tóm tắt hội thoại | Timeline điều dưỡng hiển thị `Đang phân tích...` khi chưa xong. |
| `POST /hotline/questions` | STT nếu voice + hồ sơ đã xác nhận + guardrail | Ngoài phạm vi/nguy hiểm thì `needs_staff_review = true`. |

SmartVision không tích hợp vào MVP vì không liên quan trực tiếp nghiệp vụ CareVoice AI.
