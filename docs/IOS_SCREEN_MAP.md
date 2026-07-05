# Sơ Đồ Màn Hình iOS CareVoice AI

Tài liệu này map màn hình iOS với endpoint trong `API_CONTRACT.md`. App dùng SwiftUI + MVVM, `NavigationView.navigationViewStyle(.stack)` cho iOS 15.

## Vào App

### Splash / Khôi Phục Phiên

- Mục tiêu: đọc token từ Keychain, role đã chọn từ UserDefaults, gọi `/me`.
- API: `GET /me`
- Trạng thái: loading "Đang mở CareVoice AI", lỗi có nút "Thử lại", nếu hết phiên thì về chọn vai trò.

### Chọn Vai Trò

- Hai lựa chọn lớn: "Tôi là bệnh nhân/người nhà" và "Tôi là điều dưỡng/bác sĩ".
- Không gọi API.
- Lưu role đã chọn sau login thành công.

### Đăng Nhập Nhân Viên

- API: `POST /auth/staff/login`
- Sau login: `POST /devices/register` với `notification_channel = "local"`.
- Điều hướng: vào bảng điều khiển nhân viên.

### Đăng Nhập Bệnh Nhân

- Luồng OTP: `POST /auth/patient/request_otp` -> `POST /auth/patient/verify_otp`
- Luồng mã bệnh nhân demo: `POST /auth/patient/login_code`
- Sau login: vào trang chủ bệnh nhân.

## Vai Trò Bệnh Nhân

### Trang Chủ Bệnh Nhân

- Buổi sáng **3 bước**: check-in, uống thuốc, xác thực khuôn mặt (`MorningRoutineTracker`).
- Hiển thị check-in hôm nay, thuốc gần tới giờ (deep-link từ thông báo), lịch tái khám gần nhất.
- API: `GET /me/checkins/today`, `GET /me/medications`, `GET /me/appointments`
- Điều hướng: Check-In, Thuốc, Tái khám, Hotline, Lịch sử.
- Trạng thái rỗng: "Hôm nay chưa có câu hỏi mới."

### Check-In Hôm Nay

- Màn hình cực đơn giản: câu hỏi to, 3 nút **Ổn / Bình thường / Có vấn đề**, mic tùy chọn, một nút gửi.
- API:
  - `GET /me/checkins/today`
  - Nếu `audio_status = generating`: poll `GET /checkins/{checkin_id}/audio`
  - (Tùy chọn) `POST /checkins/{checkin_id}/transcribe` — xem trước chữ từ ghi âm
  - Gửi: `POST /checkins/{checkin_id}/responses` (`quick_answer_id` + optional `audio_file` + optional `confirmed_transcript`)
  - Poll kết quả: `GET /checkin_jobs/{job_id}` — `risk.analysis_hints` khi có transcript
- Trạng thái:
  - loading: "Đang chuẩn bị câu hỏi..."
  - đang ghi âm: waveform/pulse, nút "Dừng"
  - nghe lại audio local: nghe lại/gửi
  - polling: "Đã nhận câu trả lời. Hệ thống đang gửi điều dưỡng xem lại nếu cần."
  - offline: lưu file vào retry queue, hiển thị "Đã lưu tạm, sẽ gửi khi có mạng."

### Lịch Sử Check-In

- Timeline đơn giản bằng icon + màu + text đời thường.
- API: `GET /me/checkins/history`
- Không hiển thị thuật ngữ `risk_score`.

### Danh Sách Thuốc

- Thẻ thuốc lớn: tên thuốc, liều, giờ uống.
- API: `GET /me/medications`
- Trạng thái rỗng: "Chưa có đơn thuốc đã xác nhận."

### Lịch Tái Khám

- Lịch tái khám, nút thêm nhắc lịch local.
- API: `GET /me/appointments`

### Hotline

- Nút mic lớn + ô nhập text. Giọng nói: ghi → dừng → **xác nhận Gửi** (không auto-send).
- API:
  - Text: `POST /hotline/questions`
  - Giọng nói: `POST /hotline/questions` multipart
  - Nếu `202`: poll `GET /hotline/questions/{question_id}`
  - Lịch sử: `GET /hotline/questions`
- Nội dung an toàn: "Câu hỏi này cần điều dưỡng xem lại" thay vì kết luận y khoa.

### Cài Đặt Bệnh Nhân

- Hồ sơ cơ bản: `GET /me/patient`
- Tuỳ chọn thông báo: `GET/PATCH /devices/{device_id}/notification_preferences`
- Đăng xuất: `POST /auth/logout`, `DELETE /devices/{device_id}`
- Đổi vai trò: xoá session + về chọn vai trò.

### eKYC Tạm Thời

- Nút "Xác thực khuôn mặt khi tái khám".
- API: `POST /identity/face_verification/sessions`, `GET /identity/face_verification/sessions/{session_id}`
- Không dành nhiều UI trong MVP.

## Vai Trò Nhân Viên

### Bảng Điều Khiển Nhân Viên

- Màn đầu là danh sách cảnh báo ưu tiên, không phải danh sách alphabet.
- Header KPI: tổng bệnh nhân, ca cần chú ý, ca cần can thiệp, tỷ lệ check-in, OCR chờ, phân tích chờ.
- API: `GET /staff/dashboard/overview`, `GET /staff/patients/priority?actionable_only=true`
- Danh sách: `List` hoặc `LazyVStack`, pull-to-refresh bằng `.refreshable`.
- Cell: `PatientCard` + `RiskBadge` có màu, icon, text.

### Chi Tiết Bệnh Nhân

- Header hồ sơ ngắn: tên, tuổi, bệnh nền, SĐT/người nhà.
- Timeline dọc: phát audio BN, transcript, gợi ý phân tích giọng, đánh dấu đã gọi lại.
- API:
  - `GET /patients/{patient_id}`
  - `GET /staff/patients/{patient_id}/timeline`
  - Hành động: `PATCH /staff/patients/{patient_id}/timeline/{entry_id}/handling`
- Nếu entry có `status = analyzing`: `PollingStatusView` "Đang phân tích phản hồi..."
- Hành động khi entry completed: "Đánh dấu đã xem", "Gọi lại", "Ghi chú xử lý".

### Tạo Hồ Sơ Bệnh Nhân

- Form tạo bệnh nhân tối giản theo nhóm thông tin.
- API: `POST /patients`
- Sau tạo: đi tới tải tài liệu y tế.

### Tải Lên Tài Liệu Y Tế

- Chọn ảnh/PDF từ camera/photo/file.
- API: `POST /patients/{patient_id}/documents`
- Phản hồi nhận `job_id`, chuyển sang màn xử lý OCR.
- UI không chặn cứng; có thể quay về dashboard, badge OCR đang chờ.

### Xử Lý OCR

- `PollingStatusView` với tiến độ/stage đời thường.
- API: poll `GET /ocr/jobs/{job_id}`
- Hành động huỷ: `POST /ocr/jobs/{job_id}/cancel`
- Khi `needs_review`: vào rà soát OCR.

### Rà Soát Và Xác Nhận OCR

- Danh sách thuốc có thể sửa: tên, hàm lượng, liều, giờ uống, hướng dẫn.
- API: `POST /patients/{patient_id}/documents/{upload_id}/confirm_ocr`
- Bắt buộc người kiểm tra: không tự lưu OCR.

### Tìm Kiếm Và Lọc

- Tìm theo tên, mã bệnh nhân, SĐT; lọc risk/handling status.
- API: `GET /staff/patients/priority?query=...&risk_level=...`

### Cài Đặt Nhân Viên

- Hồ sơ: `GET /me`
- Tuỳ chọn thông báo: `GET/PATCH /devices/{device_id}/notification_preferences`
- Đăng xuất/đổi vai trò: `POST /auth/logout`, `DELETE /devices/{device_id}`

## Luồng Thông Báo

- Không xin quyền notification ngay khi mở lần đầu.
- Bệnh nhân: xin sau lần check-in/onboarding đầu tiên, giải thích nhắc check-in/thuốc/tái khám.
- Nhân viên: xin sau khi vào dashboard, giải thích app dùng local reminder và polling khi chưa có APNs.
- API đăng ký thiết bị: `POST /devices/register` với `notification_channel = "local"`.
- Local reminder: check-in, thuốc, tái khám.
- Cảnh báo staff khi chưa có Apple Developer: app poll dashboard/timeline khi mở; nếu cần server push miễn phí thì làm PWA Web Push riêng cho staff.

## Quy Tắc Điều Hướng iOS 15

- Dùng `NavigationView`, không dùng `NavigationStack`/`NavigationSplitView`.
- Mọi màn hình iPad ép `.navigationViewStyle(.stack)`.
- Sheet trên iOS 15 không dùng `.presentationDetents`; nếu cần bottom sheet thì dùng full-screen/UIViewControllerRepresentable fallback.
