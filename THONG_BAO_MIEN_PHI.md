# Thông Báo Miễn Phí Không Cần Apple Developer

## Chọn Phương Án

- Native iOS: dùng local notification cho nhắc check-in, uống thuốc và tái khám.
- Backend: lưu thiết bị và tuỳ chọn thông báo, nhưng không gửi remote push khi chưa có APNs.
- Cảnh báo nhân viên gần real-time miễn phí: làm thêm PWA dashboard và dùng Web Push cho web app đã thêm vào Home Screen.
- Sau MVP: nếu có Apple Developer thì bật APNs cho native iOS.

## Lý Do

- Local notification chạy trên iPhone sau khi app xin quyền, không cần Apple Developer Program.
- Native remote push trên iOS phải đi qua APNs và cần Push Notifications capability.
- Web Push trên iOS/iPadOS hỗ trợ web app đã thêm vào Home Screen từ iOS/iPadOS 16.4.

## Luồng Đã Áp Dụng

1. Sau login, app gọi `POST /devices/register` với `notification_channel = "local"`.
2. Khi user bật thông báo, app xin quyền bằng `UNUserNotificationCenter`.
3. App đặt local reminder theo tuỳ chọn: check-in, thuốc, tái khám.
4. Nếu user tắt một nhóm reminder, app xoá pending notification tương ứng.
5. Cảnh báo nhân viên khi chưa có APNs dùng polling dashboard/timeline khi app đang mở.

## Tài Liệu Tham Khảo

- Apple local notification: <https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app>
- Apple đăng ký APNs: <https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns>
- WebKit Web Push cho Home Screen web app: <https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/>
