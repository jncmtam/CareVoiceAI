# Tài liệu CareVoice AI

Bộ tài liệu dùng cho phát triển, demo hackathon và thuyết trình. **Tên file tiếng Anh**, **nội dung tiếng Việt**.

## Mục lục

| File | Mục đích |
|------|----------|
| [SYSTEM_OVERVIEW.md](SYSTEM_OVERVIEW.md) | Kiến trúc hệ thống, thành phần, luồng dữ liệu |
| [FEATURES_AND_FLOWS.md](FEATURES_AND_FLOWS.md) | Chức năng chi tiết theo vai trò bệnh nhân / điều dưỡng |
| [PRODUCT_PITCH_SOLO.md](PRODUCT_PITCH_SOLO.md) | Script thuyết trình **1 người** (~4–5 phút) |
| [SETUP_AND_ACCOUNTS.md](SETUP_AND_ACCOUNTS.md) | Chạy backend, iOS, tài khoản, chế độ demo |
| [API_CONTRACT.md](API_CONTRACT.md) | Hợp đồng REST API (iOS ↔ backend) |
| [IOS_SCREEN_MAP.md](IOS_SCREEN_MAP.md) | Map màn hình iOS |
| [IOS_PROJECT_BLUEPRINT.md](IOS_PROJECT_BLUEPRINT.md) | Cấu trúc project Xcode |
| [FREE_NOTIFICATIONS.md](FREE_NOTIFICATIONS.md) | Thông báo local không cần Apple Developer |
| [VNPT_INTEGRATION_NOTES.md](VNPT_INTEGRATION_NOTES.md) | Ghi chú tích hợp STT/TTS/SmartBot/OCR VNPT |

## Tài nguyên test

File mẫu dùng cho pytest và script demo nằm tại `backend/test/`:

- `test/stt/STT.sample.wav` — mẫu STT live VNPT
- `test/ocr/don_thuoc_chu_minh_tam.docx` — đơn thuốc OCR
- `test/tts/generated/` — output TTS khi chạy `scripts/vnpt_sample_wav_demo.py`

## Cập nhật

Khi đổi credential, API hoặc flow demo, cập nhật **SETUP_AND_ACCOUNTS.md** và **FEATURES_AND_FLOWS.md** trước khi pitch.