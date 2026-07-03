# Danh Sách Model Codable

Danh sách model Swift dựa trên `API_CONTRACT.md`. JSON decoder dùng `keyDecodingStrategy = .convertFromSnakeCase`; vẫn có thể thêm `CodingKeys` ở model nhạy cảm để rõ contract.

## Enum Dùng Chung

```swift
enum UserRole: String, Codable { case patient, caregiver, nurse, doctor, admin }
enum RiskLevel: String, Codable { case normal, attention, intervention }
enum JobStatus: String, Codable { case queued, uploading, processing, transcribing, analyzing, summarizing, needsReview = "needs_review", completed, failed, cancelled, expired }
enum AudioStatus: String, Codable { case ready, generating, unavailable, failed }
enum DocumentType: String, Codable { case prescription, dischargeNote = "discharge_note" }
enum OcrMode: String, Codable { case auto, basic, table }
enum HandlingStatus: String, Codable { case new, viewed, calledBack = "called_back", resolved }
enum TimelineEntryType: String, Codable { case checkinResponse = "checkin_response", hotlineQuestion = "hotline_question", medicationUpdate = "medication_update", appointment }
enum PushEnvironment: String, Codable { case sandbox, production }
enum NotificationChannel: String, Codable { case local, webPush = "web_push", apns }
```

## Model Dùng Chung

- `APIErrorEnvelope`
- `APIErrorBody`
- `EmptyResponse`
- `PaginationMeta`
- `PaginatedResponse<T: Codable>`
- `AnyCodableValue` chỉ dùng khi backend cần `details` bất kỳ; mặc định dùng `[String: String]`.

## Model Xác Thực

- `StaffLoginRequest`
- `PatientOtpRequest`
- `PatientOtpResponse`
- `PatientOtpVerifyRequest`
- `PatientCodeLoginRequest`
- `AuthResponse`
- `TokenPair`
- `RefreshTokenRequest`
- `RefreshTokenResponse`
- `LogoutRequest`
- `CurrentUserResponse`
- `AppUser`
- `PatientSessionContext`

## Model Bệnh Nhân/Hồ Sơ

- `PatientCreateRequest`
- `PatientUpdateRequest`
- `PatientResponse`
- `PatientProfile`
- `PatientSummary`
- `DiagnosisCode`
- `Gender`
- `FollowUpDraft`
- `Appointment`
- `AppointmentListResponse`
- `Medication`
- `MedicationDraft`
- `MedicationListResponse`
- `MedicationTimeOfDay`
- `MedicalDocument`

## Model OCR

- `DocumentUploadResponse`
- `OCRJobResponse`
- `OCRDraftMedication`
- `OCRDraftFollowUp`
- `OCRConfirmRequest`
- `OCRConfirmResponse`
- `OCRWarning`
- `CancelJobRequest`
- `CancelJobResponse`

## Model Check-In

- `TodayCheckinResponse`
- `Checkin`
- `QuickAnswer`
- `CheckinAudioStatusResponse`
- `SubmitCheckinResponse`
- `CheckinJobResponse`
- `RiskAssessment`
- `CheckinHistoryItem`
- `CheckinHistoryResponse`

## Model Bảng Điều Khiển/Nhân Viên

- `DashboardOverview`
- `PriorityPatientSummary`
- `PriorityPatientListResponse`
- `PatientTimelineResponse`
- `TimelineEntry`
- `TimelinePatientHeader`
- `HandlingUpdateRequest`
- `HandlingUpdateResponse`
- `HandledByUser`

## Model Hotline

- `HotlineQuestionTextRequest`
- `HotlineQuestionResponse`
- `HotlineQuestionStatusResponse`
- `HotlineHistoryItem`
- `HotlineHistoryResponse`

Hotline bằng giọng nói dùng multipart nên phần yêu cầu do `MultipartFormDataBuilder` tạo, không nhất thiết có Codable request.

## Model Thông Báo

- `DeviceRegistrationRequest`
- `DeviceRegistrationResponse`
- `NotificationChannel`
- `NotificationPreferences`
- `NotificationPreferencesUpdateRequest`
- `NotificationPreferencesResponse`

## Model eKYC Tạm Thời

- `FaceVerificationSessionRequest`
- `FaceVerificationSessionResponse`
- `FaceVerificationStatusResponse`

## Model Chỉ Dùng Local

Các model này không map trực tiếp API nhưng cần cho production iOS:

- `SessionState`
- `SelectedRolePreference`
- `OfflineUploadItem`
- `OfflineUploadStatus`
- `AudioRecordingState`
- `PollingState<Value>`
- `LoadableState<Value>`
- `AppRoute`
- `PatientTab`
- `StaffTab`

## Ánh Xạ API Với Model

| API | Model yêu cầu | Model phản hồi |
| --- | --- | --- |
| `POST /auth/staff/login` | `StaffLoginRequest` | `AuthResponse` |
| `POST /auth/patient/request_otp` | `PatientOtpRequest` | `PatientOtpResponse` |
| `POST /auth/patient/verify_otp` | `PatientOtpVerifyRequest` | `AuthResponse` |
| `POST /auth/patient/login_code` | `PatientCodeLoginRequest` | `AuthResponse` |
| `POST /auth/refresh` | `RefreshTokenRequest` | `RefreshTokenResponse` |
| `GET /me` | không có | `CurrentUserResponse` |
| `POST /patients` | `PatientCreateRequest` | `PatientResponse` |
| `GET /patients/{id}` | không có | `PatientResponse` |
| `PATCH /patients/{id}` | `PatientUpdateRequest` | `PatientResponse` |
| `POST /patients/{id}/documents` | multipart | `DocumentUploadResponse` |
| `GET /ocr/jobs/{job_id}` | không có | `OCRJobResponse` |
| `POST /patients/{id}/documents/{upload_id}/confirm_ocr` | `OCRConfirmRequest` | `OCRConfirmResponse` |
| `GET /me/checkins/today` | không có | `TodayCheckinResponse` |
| `GET /checkins/{id}/audio` | không có | `CheckinAudioStatusResponse` |
| `POST /checkins/{id}/responses` | multipart | `SubmitCheckinResponse` |
| `GET /checkin_jobs/{job_id}` | không có | `CheckinJobResponse` |
| `GET /staff/dashboard/overview` | không có | `DashboardOverview` |
| `GET /staff/patients/priority` | tham số query | `PriorityPatientListResponse` |
| `GET /staff/patients/{id}/timeline` | tham số query | `PatientTimelineResponse` |
| `PATCH /staff/patients/{id}/timeline/{entry_id}/handling` | `HandlingUpdateRequest` | `HandlingUpdateResponse` |
| `POST /hotline/questions` | `HotlineQuestionTextRequest` hoặc multipart | `HotlineQuestionResponse` |
| `GET /hotline/questions/{id}` | không có | `HotlineQuestionStatusResponse` |
| `POST /devices/register` | `DeviceRegistrationRequest` | `DeviceRegistrationResponse` |
| `GET /devices/{id}/notification_preferences` | không có | `NotificationPreferencesResponse` |
| `PATCH /devices/{id}/notification_preferences` | `NotificationPreferencesUpdateRequest` | `NotificationPreferencesResponse` |
