# Backend CareVoice AI

Backend REST API cho iOS app CareVoice AI. API bám `docs/API_CONTRACT.md` và Swift Codable model: JSON `snake_case`, datetime ISO 8601 UTC có hậu tố `Z`, lỗi theo envelope `{ "error": ... }`, job polling cho OCR/check-in/hotline.

## Kiến trúc

- **FastAPI + Pydantic v2**: sinh OpenAPI chuẩn, validation chặt, response model ổn định cho frontend.
- **SQLAlchemy 2.0 async**: chạy SQLite local, đổi sang PostgreSQL bằng `DATABASE_URL` mà không đổi code.
- **Service + repository**: route mỏng, nghiệp vụ nằm ở service, query lặp lại nằm ở repository.
- **JWT + refresh token rotation**: refresh token lưu dạng hash, revoke khi logout/rotate.
- **RBAC**: `patient/caregiver` chỉ xem hồ sơ của mình; `nurse/doctor/admin` xem dashboard, OCR và xử lý timeline.
- **Job model**: OCR, TTS, phân tích check-in, hotline voice dùng status chung `queued|processing|needs_review|completed|failed|...`.
- **Background jobs**: `app/services/job_runner.py` chạy OCR/check-in/hotline async khi `VENDOR_MOCK_MODE=false`, delay ngắn sau `commit` để tránh race với request.
- **Storage limits**: upload theo loại file — document/PDF/ảnh tối đa 25MB, audio tối đa 250MB, media sinh ra từ TTS tối đa 50MB; vượt giới hạn trả `413 file_too_large`.
- **Cổng VNPT**: `app/integrations/vnpt/` gồm mock adapter và live gateway; production dùng SmartReader, SmartVoice, STT/SmartBot.
- **Offline sync/idempotency**: endpoint có retry dùng `client_request_id` và bảng `idempotency_keys`.
- **Middleware production**: trace id, lỗi có cấu trúc, CORS, GZip, security headers, rate limiting, health check.

## Cấu trúc thư mục

```text
backend/
  app/
    api/              # router FastAPI + dependency
    core/             # cấu hình, bảo mật, lỗi, logging
    db/               # engine/session async, tạo bảng, seed demo
    integrations/     # adapter VNPT/vendor
    middleware/       # trace-id, rate limiting
    models/           # entity SQLAlchemy + enum
    repositories/     # helper query
    schemas/          # schema Pydantic cho contract
    services/         # workflow nghiệp vụ
    utils/            # ids, datetime
  migrations/         # Alembic scaffold
  test/               # File mẫu: stt/, ocr/, tts/
  tests/              # Pytest
```

## Thiết Kế Database

Nhóm bảng chính:

- `users`, `refresh_tokens`, `otp_sessions`, `patient_users`
- `patients`, `medications`, `appointments`, `medical_documents`
- `jobs`, `checkins`, `checkin_responses`, `hotline_questions`
- `staff_alerts`, `devices`
- `idempotency_keys`

Chi tiết đã chuẩn bị cho production:

- ID dạng string có prefix theo domain.
- Unique constraint cho mã bệnh nhân và request idempotent.
- Foreign key cho ownership/scope.
- Audit timestamp trên mọi entity.
- Soft delete cho dữ liệu không nên xoá vật lý.
- Cột version cho hồ sơ clinical/profile để sau này optimistic locking.
- Index cho dashboard ưu tiên, lọc risk, tra bệnh nhân, job, thiết bị và cảnh báo.

## Nhóm API

- Xác thực: `/auth/staff/login`, `/auth/patient/request_otp`, `/auth/patient/verify_otp`, `/auth/patient/login_code`, `/auth/refresh`, `/auth/logout`, `/me`
- Bệnh nhân/hồ sơ: `/patients`, `/patients/{id}`, `/me/patient`
- Thuốc/tái khám: `/patients/{id}/medications`, `/me/medications`, `/patients/{id}/appointments`, `/me/appointments`
- OCR: `/patients/{id}/documents`, `/ocr/jobs/{job_id}`, `/ocr/jobs/{job_id}/cancel`, `/patients/{id}/documents/{upload_id}/confirm_ocr`
- Check-in: `/me/checkins/today`, `/checkins/{id}/audio`, `/checkins/{id}/responses`, `/checkin_jobs/{job_id}`, `/me/checkins/history`
- Bảng điều khiển nhân viên: `/staff/dashboard/overview`, `/staff/patients/priority`, `/staff/patients/{id}/timeline`, cập nhật handling
- Hotline: `/hotline/questions`, `/hotline/questions/{id}`, `/hotline/questions`
- Thiết bị: `/devices/register`, `/devices/{id}`, `GET/PATCH /devices/{id}/notification_preferences`

## Chạy Local

```bash
# Từ root repo (khuyến nghị)
make setup && make backend

# Hoặc thủ công
cd backend
cp .env.example .env   # chỉnh VENDOR_MOCK_MODE=true cho demo nhanh
./scripts/start_local.sh
```

OpenAPI: `http://127.0.0.1:8000/api/v1/docs`

Tài khoản demo (đồng bộ mỗi startup — xem `app/db/production_accounts.py`):

- Nhân viên: `nurse` / `nurse` (Ngô Ngọc Triệu Mẫn)
- Bệnh nhân: `patient` / `patient` hoặc `VC-2026-000001` + 4 số cuối SĐT `8468` (Chu Minh Tâm)
- Người nhà: Trần Minh Anh — `+84987654321` (SMS mock khi cảnh báo)
- OTP demo: `123456`

Chi tiết: [docs/SETUP_AND_ACCOUNTS.md](../docs/SETUP_AND_ACCOUNTS.md)

Base URL mặc định của iOS app là `http://127.0.0.1:8000/api/v1`; tắt demo mode trong Cài đặt để gọi backend này.

## Docker

```bash
cd backend
docker compose up --build
```

Compose chạy API + PostgreSQL + Redis. Bản local vẫn dùng rate limit/job mock trong bộ nhớ; Redis dành cho production: rate limit phân tán, queue, cache và fanout thông báo.

## Quy Tắc Offline Sync

- Client phải gửi `client_request_id` khi upload tài liệu, gửi check-in và hỏi hotline.
- Cùng body + cùng `client_request_id` trả lại response cũ.
- Hotline voice: cùng `client_request_id` (kể cả audio hash hơi khác do file finalize) trả lại câu hỏi đã tạo.
- Check-in/OCR: cùng `client_request_id` nhưng khác body có thể trả `409 conflict`.
- Backend lưu response tức thời trong `idempotency_keys`.
- Job polling có thể retry an toàn và giữ terminal state tới khi hết retention.

## Việc Cần Làm Cho Production

- Đặt `AUTO_CREATE_TABLES=false`; dùng Alembic migration.
- Thay `VNPTGateway` mock bằng HTTP client thật cho SmartReader/SmartVoice/STT/SmartBot.
- Chuyển rate limiting, cleanup idempotency và revoke session sang Redis/Celery hoặc RQ.
- Lưu media trên object storage tương thích S3 thay vì `storage/` local.
- Native iOS đang dùng local notification miễn phí; chỉ thêm APNs provider khi đã có Apple Developer.
- Nếu cần server push miễn phí trước APNs, làm thêm PWA staff dashboard dùng Web Push.
- Thêm metrics exporter như Prometheus khi biết môi trường deploy.
- Bổ sung retention policy cho PHI/PII, export audit log, mã hoá at-rest và quy trình backup/restore.

## Kiểm Thử

```bash
make test                    # pytest
make smoke                   # smoke test (API phải đang chạy)
make demo-check              # pytest + smoke + patient-flow × 3
```

Chi tiết checklist: [TESTING.md](../TESTING.md)

Test hiện kiểm tra auth/dashboard, check-in submit/poll (+ SMS người nhà), OCR upload/poll/confirm (kể cả docx), hotline STT/SmartBot, đăng ký local notification, envelope lỗi, storage limits (`413`/`415`), background jobs và STT parser VNPT.

File mẫu: `test/stt/STT.sample.wav`, `test/ocr/don_thuoc_chu_minh_tam.docx`. Demo VNPT: `python scripts/vnpt_sample_wav_demo.py`.