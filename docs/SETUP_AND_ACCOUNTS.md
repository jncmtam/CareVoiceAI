# Thiết lập & tài khoản

Hướng dẫn chạy CareVoice AI cho demo hackathon với backend thật.

## Yêu cầu

- macOS + Xcode 15+ (iOS 15+)
- Python 3.12
- Docker (tuỳ chọn, cho PostgreSQL)

## Backend

### Cách 1 — Python trực tiếp (khuyến nghị demo / hackathon)

**Không cần Docker.** Dùng SQLite, tài khoản `nurse`/`patient` vẫn đủ.

```bash
cd backend
./scripts/start_local.sh
```

Nếu port 8000 đang bị Docker chiếm:

```bash
docker compose down
./scripts/start_local.sh
```

OpenAPI: `http://127.0.0.1:8000/api/v1/docs`

### Cách 2 — Docker (PostgreSQL + Redis, giống production hơn)

```bash
cd backend
docker compose up --build
```

**Log Docker ngắn?** Bình thường — container đã chạy thì `docker compose up` chỉ báo `Healthy`, không in lại startup. Xem log đầy đủ:

```bash
docker compose logs -f api          # theo dõi realtime
docker compose logs api --tail 100  # 100 dòng gần nhất
docker compose up --force-recreate api   # khởi động lại API → thấy log boot mới
```

Log `/healthz` (healthcheck mỗi 30s) bị ẩn cố ý để không spam. Log request thật (login, check-in…) sẽ hiện khi app gọi API.

### Chế độ mock vs VNPT live

| Biến | Demo nhanh | Pitch có AI thật |
|------|------------|------------------|
| `VENDOR_MOCK_MODE` | `true` | `false` |
| Credential VNPT | Không cần | Điền trong `.env` |

Script kiểm tra VNPT live:

```bash
cd backend
python scripts/vnpt_sample_wav_demo.py          # STT + TTS + SmartBot với WAV mẫu
python scripts/vnpt_live_check.py               # smoke test toàn cổng
```

## iOS

1. Mở `CareVoiceAI.xcodeproj` trong Xcode.
2. Tab **Cài đặt** → tắt **Demo mode**.
3. **Kết nối backend** → nhập `http://<IP-Mac>:8000/api/v1` (iPhone thật **không** dùng `127.0.0.1`).
4. Bấm kiểm tra kết nối → đăng nhập.

`Info.plist` đã bật `NSAllowsLocalNetworking` và `NSLocalNetworkUsageDescription` cho mạng LAN.

**Quan trọng (iPhone thật):** Lần đầu mở màn đăng nhập, iOS hỏi **「Cho phép tìm thiết bị trên mạng cục bộ?」** → bấm **Cho phép**. Nếu đã từ chối trước đó: Cài đặt iOS → CareVoice AI → bật **Mạng cục bộ**, hoặc gỡ app cài lại.

## Tài khoản chuẩn (production/demo thống nhất)

Nguồn: `backend/app/db/production_accounts.py` — đồng bộ mỗi lần khởi động API.

| Vai trò | Đăng nhập | Mật khẩu / ghi chú |
|---------|-----------|-------------------|
| **Điều dưỡng** | `nurse` (ô email/mã) | `nurse` |
| **Bệnh nhân** | `patient` | `patient` |
| **Bệnh nhân (mã)** | `VC-2026-000001` | 4 số cuối SĐT: **`8468`** |
| **OTP demo** | SĐT khớp hồ sơ | **`123456`** |

### Bệnh nhân chính demo

| Trường | Giá trị |
|--------|---------|
| Họ tên | **Chu Minh Tâm** |
| Mã BN | `VC-2026-000001` |
| ID backend | `pat_001` |
| SĐT | `0327628468` / `+84327628468` |
| Người nhà | **Trần Minh Anh** — `+84987654321` |
| Chẩn đoán | Đái tháo đường type 2, tăng huyết áp |

Khi check-in/hotline ở mức **attention** hoặc **intervention**, backend ghi log SMS mock tới người nhà (nếu có `caregiver_phone_number`).

## Kiểm thử nhanh

```bash
cd backend
python -m pytest -q
./scripts/smoke_test_localhost.sh
./scripts/patient_flow_test.sh
```

## Lỗi thường gặp

| Triệu chứng | Cách xử lý |
|-------------|------------|
| iPhone không kết nối backend | Dùng IP LAN Mac, cùng Wi-Fi, tắt demo mode |
| Hotline/OCR lỗi sau đổi schema | Recreate DB Docker volume hoặc xoá `*.db` local |
| VNPT 401/403 | Kiểm tra token trong `.env`, chạy `vnpt_live_check.py` |