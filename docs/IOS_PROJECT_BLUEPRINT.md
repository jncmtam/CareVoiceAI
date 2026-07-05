# Bản Thiết Kế Dự Án iOS

Mục tiêu implementation: iOS 15.0+, SwiftUI chính, MVVM, không dùng API iOS 16+ nếu không có fallback.

## Cấu Trúc Thư Mục Đề Xuất

```text
CareVoiceAI/
  CareVoiceAIApp.swift
  App/
    AppEnvironment.swift
    AppConstants.swift
    RootView.swift
  Models/
    AuthModels.swift
    PatientModels.swift
    OCRModels.swift
    CheckinModels.swift
    DashboardModels.swift
    HotlineModels.swift
    NotificationModels.swift
    CommonModels.swift
  Networking/
    APIClient.swift
    APIEndpoint.swift
    APIError.swift
    MultipartFormDataBuilder.swift
    RequestBuilder.swift
    TokenStore.swift
    AsyncPoller.swift
  Services/
    SessionManager.swift
    AudioRecorderService.swift
    AudioPlaybackService.swift
    AudioCache.swift
    OfflineUploadQueue.swift
    ReachabilityMonitor.swift
    NotificationManager.swift
    HapticsManager.swift
  ViewModels/
    Auth/
      RoleSelectionViewModel.swift
      StaffLoginViewModel.swift
      PatientLoginViewModel.swift
    PatientRole/
      PatientHomeViewModel.swift
      TodayCheckinViewModel.swift
      CheckinHistoryViewModel.swift
      MedicationListViewModel.swift
      AppointmentListViewModel.swift
      HotlineViewModel.swift
    NurseRole/
      StaffDashboardViewModel.swift
      PatientDetailViewModel.swift
      NewPatientViewModel.swift
      DocumentUploadViewModel.swift
      OCRReviewViewModel.swift
    SettingsViewModel.swift
  Views/
    Shared/
      PrimaryButton.swift
      SecondaryButton.swift
      DestructiveButton.swift
      RiskBadge.swift
      PatientCard.swift
      TimelineEntryRow.swift
      RecordingButton.swift
      EmptyStateView.swift
      LoadingView.swift
      ErrorBannerView.swift
      PollingStatusView.swift
      FormField.swift
    Auth/
      RoleSelectionView.swift
      StaffLoginView.swift
      PatientLoginView.swift
      OTPVerificationView.swift
    PatientRole/
      PatientHomeView.swift
      TodayCheckinView.swift
      CheckinHistoryView.swift
      MedicationListView.swift
      AppointmentListView.swift
      HotlineView.swift
      FaceVerificationPlaceholderView.swift
    NurseRole/
      StaffDashboardView.swift
      PatientDetailView.swift
      NewPatientView.swift
      DocumentUploadView.swift
      OCRProcessingView.swift
      OCRReviewView.swift
    Settings/
      SettingsView.swift
  Utils/
    DateFormatters.swift
    FileStorage.swift
    AccessibilityHelpers.swift
    Localized.swift
    ImageResize.swift
  Resources/
    Assets.xcassets/
    vi.lproj/Localizable.strings
    Info.plist
```

## Thứ Tự Xây Dựng

1. Networking layer + `AsyncPoller`
2. Session/auth state + token store trong Keychain
3. Component dùng chung + design token
4. Xác thực/chọn vai trò
5. Luồng bệnh nhân
6. Luồng nhân viên
7. Local notification + hàng đợi retry offline
8. Accessibility + kiểm tra availability iOS 15

## Ràng Buộc iOS 15

- Dùng `NavigationView`, không dùng `NavigationStack` hoặc `NavigationSplitView`.
- Luôn áp dụng `.navigationViewStyle(.stack)`.
- Được dùng `.refreshable` trên iOS 15.
- Tránh `.scrollBounceBehavior`, `.contentMargins`, Swift Charts, `.presentationDetents`.
- Danh sách dài dùng `List` hoặc `LazyVStack`; không dùng `VStack` thường cho patient/timeline.
- Ghi âm bọc `AVAudioRecorder` trong service, giữ state SwiftUI nhỏ.
- Dùng cache audio local cho TTS và file ghi âm.
- Mọi text đi qua `Localizable.strings`.
- Nút chính cho bệnh nhân có vùng chạm tối thiểu 56x56.

## Design Token

- Màu y tế chính: teal/xanh lục lam đậm, có biến thể dark mode trong Asset Catalog.
- Màu risk:
  - normal: green
  - attention: amber
  - intervention: red
- Typography: SF Pro hệ thống + Dynamic Type, không dùng body text quá nhỏ cho vai trò bệnh nhân.
- Icon: SF Symbols.

## State Dùng Chung

- `SessionManager`: `EnvironmentObject`, giữ role, token, current user, logout, restore.
- `APIClient`: inject qua environment hoặc init của view model.
- `OfflineUploadQueue`: lưu metadata upload audio đang chờ + file URL.
- `NotificationManager`: xin quyền đúng thời điểm, đăng ký thiết bị kênh `local`, đặt/huỷ local reminder.
- APNs chỉ dùng sau MVP khi đã có Apple Developer; server push miễn phí có thể làm bằng PWA Web Push cho staff dashboard.

## Chuẩn Polling

`AsyncPoller` cần nhận:

- closure async trả response
- điều kiện hoàn tất
- điều kiện thất bại
- `poll_after_seconds` từ server
- timeout tối đa
- exponential backoff có jitter
- huỷ khi view biến mất

Dùng cho OCR, phân tích check-in, trạng thái audio TTS, hotline voice và eKYC tạm thời.
