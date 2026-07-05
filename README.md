# CareVoice AI

Ứng dụng iOS + backend FastAPI hỗ trợ bệnh nhân mạn tính **check-in bằng giọng nói** và giúp điều dưỡng **ưu tiên can thiệp** nhờ AI (VNPT STT/TTS/SmartReader/SmartBot).

**Flow demo chính:** Bệnh nhân check-in → AI phân tích giọng/chữ → kết quả nguy cơ → điều dưỡng thấy timeline ưu tiên.

## Quick Start

### Yêu cầu

| Thành phần | Phiên bản |
|------------|-----------|
| Python | **3.12+** |
| macOS + Xcode | **15+** (target iOS 15+) |
| Docker | 24+ (tuỳ chọn) |

### 1. Clone & cài backend (1 lệnh)

```bash
git clone https://github.com/jncmtam/CareVoiceAI && cd CareVoiceAI

make backend
```

Tạo file env (điền thông tin API Key vào .env):

```bash
cp backend/.env.example backend/.env
```

### 2. Chạy backend

```bash
make backend
```

- API: `http://127.0.0.1:8000/api/v1`
- OpenAPI: `http://127.0.0.1:8000/api/v1/docs`
- Docker (tuỳ chọn): `make docker-up`

### 3. Chạy iOS

1. Mở `CareVoiceAI.xcodeproj` trong Xcode.
2. **Cài đặt môi trường Swift code** 
3. **Kết nối backend** → `http://127.0.0.1:8000/api/v1` (Simulator) **Hệ thống Demo trên hệ điều hành iOS**
4. Đăng nhập tài khoản demo

### 4. Kiểm tra nhanh

```bash
make test          # pytest
make smoke         # flow API end-to-end (cần API đang chạy)
make demo-check    # pytest + smoke + patient-flow × 3 lần
```

Chi tiết: [TESTING.md](TESTING.md)

## Tài khoản demo

| Vai trò | Đăng nhập | Mật khẩu / OTP |
|---------|-----------|----------------|
| **Điều dưỡng** | `nurse` | `nurse` |
| **Bệnh nhân** | `patient` | `patient` |
| **Bệnh nhân (mã)** | `VC-2026-000001` | 4 số cuối SĐT: `8468` |
| **OTP** | `+84327628468` | `123456` |

Bệnh nhân chính: **Chu Minh Tâm** — xem [docs/SETUP_AND_ACCOUNTS.md](docs/SETUP_AND_ACCOUNTS.md).

## Cấu trúc repo

| Thư mục | Mô tả |
|---------|-------|
| `CareVoiceAI/` | App iOS (SwiftUI) |
| `backend/` | API FastAPI + tích hợp VNPT |
| `backend/test/` | File mẫu STT/OCR cho demo & test |
| `backend/tests/` | Pytest tự động |
| `backend/scripts/` | Smoke test, start local, VNPT check |
| `docs/` | Kiến trúc, API contract, flow demo |
| `scripts/` | Script repo-level (submission checks) |

## Tính năng AI (MVP)

| Tính năng | AI làm gì | Hành động tiếp theo |
|-----------|-----------|---------------------|
| Check-in hàng ngày | TTS đọc câu hỏi, STT ghi âm, phân loại nguy cơ | Badge + lý do; điều dưỡng ưu tiên |
| Hotline | SmartBot trả lời câu hỏi thuốc/sức khỏe | Gợi ý an toàn; alert nếu nguy hiểm |
| OCR đơn thuốc | SmartReader trích xuất thuốc | Điều dưỡng xác nhận → lịch nhắc BN |

Xử lý lỗi: loading khi poll job, banner lỗi API/mất mạng, queue offline upload.

## Bảo mật & credential

- Token VNPT **chỉ** trong `backend/.env` (đã gitignore).
- Mẫu env: `backend/.env.example` — **không** commit `.env` thật.
- iOS không giữ token VNPT; mọi AI call qua backend.
- Log API: `request_completed` / `request_failed` — không in JWT/CCCD/ảnh.

## Tài liệu

| File | Nội dung |
|------|----------|
| [docs/README.md](docs/README.md) | Mục lục tài liệu |
| [docs/SETUP_AND_ACCOUNTS.md](docs/SETUP_AND_ACCOUNTS.md) | Cài đặt chi tiết + troubleshooting |
| [docs/FEATURES_AND_FLOWS.md](docs/FEATURES_AND_FLOWS.md) | Luồng bệnh nhân / điều dưỡng |
| [docs/API_CONTRACT.md](docs/API_CONTRACT.md) | REST API contract |
| [TESTING.md](TESTING.md) | Test tự động + checklist thủ công |
| [backend/README.md](backend/README.md) | Kiến trúc backend |

## Lệnh Makefile

```bash
make help          # Danh sách lệnh
make setup         # Venv + .env
make backend       # Chạy API local
make test          # Pytest
make smoke         # Smoke test
make patient-flow  # Test luồng bệnh nhân
make demo-check    # Kiểm tra submission (×3)
make docker-up     # Docker Compose
```
