import Foundation
import UIKit

nonisolated final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let session: URLSession
    private let tokenStore: TokenStore

    var baseURL: URL {
        URL(string: AppConstants.apiBaseURL) ?? URL(string: AppConstants.defaultBaseURL)!
    }

    init(session: URLSession = .shared, tokenStore: TokenStore = .shared) {
        self.session = session
        self.tokenStore = tokenStore
    }

    func send<Response: Decodable>(_ endpoint: APIEndpoint, requiresAuth: Bool = true) async throws -> Response {
        try await send(endpoint, requiresAuth: requiresAuth, allowRefreshRetry: true)
    }

    func sendEmpty(_ endpoint: APIEndpoint, requiresAuth: Bool = true) async throws {
        try await sendEmpty(endpoint, requiresAuth: requiresAuth, allowRefreshRetry: true)
    }

    func upload<Response: Decodable>(
        path: String,
        fields: [String: String],
        files: [MultipartFile],
        requiresAuth: Bool = true
    ) async throws -> Response {
        try await upload(path: path, fields: fields, files: files, requiresAuth: requiresAuth, allowRefreshRetry: true)
    }

    private func send<Response: Decodable>(
        _ endpoint: APIEndpoint,
        requiresAuth: Bool,
        allowRefreshRetry: Bool
    ) async throws -> Response {
        do {
            return try await sendOnce(endpoint, requiresAuth: requiresAuth)
        } catch {
            guard allowRefreshRetry, shouldRefreshAfter(error: error, requiresAuth: requiresAuth, path: endpoint.path) else {
                throw error
            }
            try await refreshAccessToken()
            return try await send(endpoint, requiresAuth: requiresAuth, allowRefreshRetry: false)
        }
    }

    private func sendEmpty(_ endpoint: APIEndpoint, requiresAuth: Bool, allowRefreshRetry: Bool) async throws {
        do {
            try await sendEmptyOnce(endpoint, requiresAuth: requiresAuth)
        } catch {
            guard allowRefreshRetry, shouldRefreshAfter(error: error, requiresAuth: requiresAuth, path: endpoint.path) else {
                throw error
            }
            try await refreshAccessToken()
            try await sendEmpty(endpoint, requiresAuth: requiresAuth, allowRefreshRetry: false)
        }
    }

    private func upload<Response: Decodable>(
        path: String,
        fields: [String: String],
        files: [MultipartFile],
        requiresAuth: Bool,
        allowRefreshRetry: Bool
    ) async throws -> Response {
        do {
            return try await uploadOnce(path: path, fields: fields, files: files, requiresAuth: requiresAuth)
        } catch {
            guard allowRefreshRetry, shouldRefreshAfter(error: error, requiresAuth: requiresAuth, path: path) else {
                throw error
            }
            try await refreshAccessToken()
            return try await upload(path: path, fields: fields, files: files, requiresAuth: requiresAuth, allowRefreshRetry: false)
        }
    }

    private func sendOnce<Response: Decodable>(_ endpoint: APIEndpoint, requiresAuth: Bool) async throws -> Response {
        let request = try makeRequest(endpoint, requiresAuth: requiresAuth)
        let (data, response) = try await perform(request)
        return try decode(Response.self, from: data, response: response)
    }

    private func sendEmptyOnce(_ endpoint: APIEndpoint, requiresAuth: Bool) async throws {
        let request = try makeRequest(endpoint, requiresAuth: requiresAuth)
        let (data, response) = try await perform(request)
        _ = try validate(data: data, response: response)
    }

    private func uploadOnce<Response: Decodable>(
        path: String,
        fields: [String: String],
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> Response {
        let builder = MultipartFormDataBuilder()
        let body = builder.build(fields: fields, files: files)
        let endpoint = APIEndpoint(
            method: .post,
            path: path,
            headers: ["Content-Type": builder.contentType],
            body: body
        )
        return try await sendOnce(endpoint, requiresAuth: requiresAuth)
    }

    private func shouldRefreshAfter(error: Error, requiresAuth: Bool, path: String) -> Bool {
        guard requiresAuth, path != "auth/refresh", tokenStore.refreshToken != nil else {
            return false
        }
        guard case APIError.server(_, _, let statusCode, _) = error, statusCode == 401 else {
            return false
        }
        return true
    }

    private func refreshAccessToken() async throws {
        try await TokenRefreshCoordinator.shared.refresh(using: tokenStore) { [self] in
            try await self.exchangeRefreshToken()
        }
    }

    private func exchangeRefreshToken() async throws -> RefreshTokenResponse {
        guard let refreshToken = tokenStore.refreshToken else {
            throw APIError.missingToken
        }
        let body = try encodedBody(RefreshTokenRequest(refreshToken: refreshToken))
        return try await sendOnce(
            APIEndpoint(method: .post, path: "auth/refresh", body: body),
            requiresAuth: false
        )
    }

    private func makeRequest(_ endpoint: APIEndpoint, requiresAuth: Bool) throws -> URLRequest {
        let absolute = baseURL.absoluteString.trimmedTrailingSlash + "/" + endpoint.path.trimmedLeadingSlash
        var components = URLComponents(string: absolute)
        if !endpoint.queryItems.isEmpty {
            components?.queryItems = endpoint.queryItems
        }
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil, endpoint.headers["Content-Type"] == nil {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if requiresAuth {
            guard let token = tokenStore.accessToken else {
                throw APIError.missingToken
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = endpoint.body
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                throw APIError.offline
            case .timedOut:
                throw APIError.timeout
            default:
                throw APIError.network(message: L10n.errorDefault)
            }
        } catch {
            throw APIError.unknown(message: L10n.errorDefault)
        }
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data, response: URLResponse) throws -> Response {
        let validData = try validate(data: data, response: response)
        do {
            return try DateFormatters.apiDecoder.decode(Response.self, from: validData)
        } catch {
            throw APIError.decoding(message: error.localizedDescription)
        }
    }

    @discardableResult
    private func validate(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network(message: L10n.errorDefault)
        }
        guard (200...299).contains(http.statusCode) else {
            if let envelope = try? DateFormatters.apiDecoder.decode(APIErrorEnvelope.self, from: data) {
                throw APIError.server(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    statusCode: http.statusCode,
                    traceId: envelope.error.traceId
                )
            }
            throw APIError.server(
                code: "http_\(http.statusCode)",
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                statusCode: http.statusCode,
                traceId: nil
            )
        }
        return data
    }

    private func encodedBody<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try DateFormatters.apiEncoder.encode(value)
        } catch {
            throw APIError.encoding(message: error.localizedDescription)
        }
    }
}

extension APIClient {
    func loginStaff(login: String, password: String) async throws -> AuthResponse {
        let body = try encodedBody(StaffLoginRequest(login: login, password: password, deviceId: DeviceIdentity.deviceID))
        let response: AuthResponse = try await send(APIEndpoint(method: .post, path: "auth/staff/login", body: body), requiresAuth: false)
        return response
    }

    func requestPatientOTP(phoneNumber: String, patientCode: String?) async throws -> PatientOtpResponse {
        let body = try encodedBody(PatientOtpRequest(phoneNumber: phoneNumber, patientCode: patientCode.nilIfEmpty))
        let response: PatientOtpResponse = try await send(APIEndpoint(method: .post, path: "auth/patient/request_otp", body: body), requiresAuth: false)
        return response
    }

    func verifyPatientOTP(sessionId: String, code: String) async throws -> AuthResponse {
        let body = try encodedBody(PatientOtpVerifyRequest(otpSessionId: sessionId, otpCode: code, deviceId: DeviceIdentity.deviceID))
        let response: AuthResponse = try await send(APIEndpoint(method: .post, path: "auth/patient/verify_otp", body: body), requiresAuth: false)
        return response
    }

    func loginPatient(login: String, password: String) async throws -> AuthResponse {
        let body = try encodedBody(PatientPasswordLoginRequest(login: login, password: password, deviceId: DeviceIdentity.deviceID))
        let response: AuthResponse = try await send(APIEndpoint(method: .post, path: "auth/patient/login", body: body), requiresAuth: false)
        return response
    }

    func loginPatientCode(patientCode: String, phoneLast4: String) async throws -> AuthResponse {
        let body = try encodedBody(PatientCodeLoginRequest(patientCode: patientCode, phoneLast4: phoneLast4, deviceId: DeviceIdentity.deviceID))
        let response: AuthResponse = try await send(APIEndpoint(method: .post, path: "auth/patient/login_code", body: body), requiresAuth: false)
        return response
    }

    func refreshToken(_ refreshToken: String) async throws -> RefreshTokenResponse {
        let body = try encodedBody(RefreshTokenRequest(refreshToken: refreshToken))
        let response: RefreshTokenResponse = try await send(APIEndpoint(method: .post, path: "auth/refresh", body: body), requiresAuth: false)
        return response
    }

    func logout(refreshToken: String?) async throws {
        let body = try encodedBody(LogoutRequest(deviceId: DeviceIdentity.deviceID, refreshToken: refreshToken))
        try await sendEmpty(APIEndpoint(method: .post, path: "auth/logout", body: body))
    }

    func me() async throws -> CurrentUserResponse {
        let response: CurrentUserResponse = try await send(APIEndpoint(method: .get, path: "me"))
        return response
    }

    func createPatient(_ request: PatientCreateRequest) async throws -> PatientResponse {
        let response: PatientResponse = try await send(APIEndpoint(method: .post, path: "patients", body: try encodedBody(request)))
        return response
    }

    func patient(id: String) async throws -> PatientResponse {
        let response: PatientResponse = try await send(APIEndpoint(method: .get, path: "patients/\(id)"))
        return response
    }

    func updatePatient(id: String, request: PatientUpdateRequest) async throws -> PatientResponse {
        let response: PatientResponse = try await send(
            APIEndpoint(method: .patch, path: "patients/\(id)", body: try encodedBody(request))
        )
        return response
    }

    func deletePatient(id: String) async throws -> PatientDeleteResponse {
        let response: PatientDeleteResponse = try await send(APIEndpoint(method: .delete, path: "patients/\(id)"))
        return response
    }

    func myPatientProfile() async throws -> PatientResponse {
        let response: PatientResponse = try await send(APIEndpoint(method: .get, path: "me/patient"))
        return response
    }

    func myDailyTip() async throws -> DailyTipResponse {
        let response: DailyTipResponse = try await send(APIEndpoint(method: .get, path: "me/daily_tip"))
        return response
    }

    func myMedications() async throws -> MedicationListResponse {
        let response: MedicationListResponse = try await send(APIEndpoint(method: .get, path: "me/medications"))
        return response
    }

    func medications(patientId: String) async throws -> MedicationListResponse {
        let response: MedicationListResponse = try await send(APIEndpoint(method: .get, path: "patients/\(patientId)/medications"))
        return response
    }

    func myAppointments() async throws -> AppointmentListResponse {
        let response: AppointmentListResponse = try await send(APIEndpoint(method: .get, path: "me/appointments"))
        return response
    }

    func appointments(patientId: String) async throws -> AppointmentListResponse {
        let response: AppointmentListResponse = try await send(APIEndpoint(method: .get, path: "patients/\(patientId)/appointments"))
        return response
    }

    func uploadDocument(patientId: String, documentType: DocumentType, mode: OcrMode, fileURL: URL) async throws -> DocumentUploadResponse {
        try UploadLimits.validateDocument(fileURL: fileURL)
        let data = try Data(contentsOf: fileURL)
        let file = MultipartFile(fieldName: "file", fileName: fileURL.lastPathComponent, mimeType: fileURL.uploadMimeType, data: data)
        let response: DocumentUploadResponse = try await upload(
            path: "patients/\(patientId)/documents",
            fields: [
                "document_type": documentType.rawValue,
                "ocr_mode": mode.rawValue,
                "client_request_id": UUID().uuidString
            ],
            files: [file]
        )
        return response
    }

    func ocrJob(id: String) async throws -> OCRJobResponse {
        let response: OCRJobResponse = try await send(APIEndpoint(method: .get, path: "ocr/jobs/\(id)"))
        return response
    }

    func cancelOCRJob(id: String, reason: String) async throws -> CancelJobResponse {
        let response: CancelJobResponse = try await send(APIEndpoint(method: .post, path: "ocr/jobs/\(id)/cancel", body: try encodedBody(CancelJobRequest(reason: reason))))
        return response
    }

    func confirmOCR(patientId: String, uploadId: String, request: OCRConfirmRequest) async throws -> OCRConfirmResponse {
        let response: OCRConfirmResponse = try await send(APIEndpoint(method: .post, path: "patients/\(patientId)/documents/\(uploadId)/confirm_ocr", body: try encodedBody(request)))
        return response
    }

    func todayCheckin() async throws -> TodayCheckinResponse {
        let response: TodayCheckinResponse = try await send(APIEndpoint(method: .get, path: "me/checkins/today"))
        return response
    }

    func checkinAudio(checkinId: String) async throws -> CheckinAudioStatusResponse {
        let response: CheckinAudioStatusResponse = try await send(APIEndpoint(method: .get, path: "checkins/\(checkinId)/audio"))
        return response
    }

    func transcribeCheckinAudio(
        checkinId: String,
        audioURL: URL,
        duration: TimeInterval?
    ) async throws -> CheckinTranscribeResponse {
        var fields: [String: String] = [:]
        if let duration {
            fields["recorded_duration_seconds"] = String(Int(duration.rounded()))
        }
        try UploadLimits.validateAudio(fileURL: audioURL)
        let files = [
            MultipartFile(
                fieldName: "audio_file",
                fileName: audioURL.lastPathComponent,
                mimeType: audioURL.uploadMimeType,
                data: try Data(contentsOf: audioURL)
            )
        ]
        let response: CheckinTranscribeResponse = try await upload(
            path: "checkins/\(checkinId)/transcribe",
            fields: fields,
            files: files
        )
        return response
    }

    func submitCheckin(
        checkinId: String,
        audioURL: URL?,
        quickAnswerId: String?,
        confirmedTranscript: String? = nil,
        patientDeclaredRiskLevel: RiskLevel? = nil,
        duration: TimeInterval?,
        clientRequestId: String = UUID().uuidString
    ) async throws -> SubmitCheckinResponse {
        var fields = [
            "client_recorded_at": ISO8601DateFormatter().string(from: Date()),
            "client_request_id": clientRequestId
        ]
        if let quickAnswerId {
            fields["quick_answer_id"] = quickAnswerId
        }
        if let confirmedTranscript, !confirmedTranscript.cvTrimmed.isEmpty {
            fields["confirmed_transcript"] = confirmedTranscript.cvTrimmed
        }
        if let patientDeclaredRiskLevel {
            fields["patient_declared_risk_level"] = patientDeclaredRiskLevel.rawValue
        }
        if let duration {
            fields["recorded_duration_seconds"] = String(Int(duration.rounded()))
        }
        var files: [MultipartFile] = []
        if let audioURL {
            try UploadLimits.validateAudio(fileURL: audioURL)
            files.append(MultipartFile(fieldName: "audio_file", fileName: audioURL.lastPathComponent, mimeType: audioURL.uploadMimeType, data: try Data(contentsOf: audioURL)))
        }
        let response: SubmitCheckinResponse = try await upload(path: "checkins/\(checkinId)/responses", fields: fields, files: files)
        return response
    }

    func checkinJob(id: String) async throws -> CheckinJobResponse {
        let response: CheckinJobResponse = try await send(APIEndpoint(method: .get, path: "checkin_jobs/\(id)"))
        return response
    }

    func checkinHistory(cursor: String? = nil) async throws -> CheckinHistoryResponse {
        var query = [URLQueryItem(name: "limit", value: "30")]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: CheckinHistoryResponse = try await send(APIEndpoint(method: .get, path: "me/checkins/history", queryItems: query))
        return response
    }

    func dashboardOverview() async throws -> DashboardOverview {
        let response: DashboardOverview = try await send(APIEndpoint(method: .get, path: "staff/dashboard/overview"))
        return response
    }

    func priorityPatients(
        page: Int = 1,
        query: String? = nil,
        riskLevel: RiskLevel? = nil,
        handlingStatus: HandlingStatus? = nil,
        actionableOnly: Bool = false
    ) async throws -> PriorityPatientListResponse {
        var items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "30")
        ]
        if let query = query?.nilIfEmpty {
            items.append(URLQueryItem(name: "query", value: query))
        }
        if let riskLevel {
            items.append(URLQueryItem(name: "risk_level", value: riskLevel.rawValue))
        }
        if let handlingStatus {
            items.append(URLQueryItem(name: "handling_status", value: handlingStatus.rawValue))
        }
        if actionableOnly {
            items.append(URLQueryItem(name: "actionable_only", value: "true"))
        }
        let response: PriorityPatientListResponse = try await send(APIEndpoint(method: .get, path: "staff/patients/priority", queryItems: items))
        return response
    }

    func patientTimeline(patientId: String, cursor: String? = nil) async throws -> PatientTimelineResponse {
        var query = [URLQueryItem(name: "limit", value: "40")]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: PatientTimelineResponse = try await send(APIEndpoint(method: .get, path: "staff/patients/\(patientId)/timeline", queryItems: query))
        return response
    }

    func staffNotifications(page: Int = 1, unreadOnly: Bool = false) async throws -> StaffNotificationListResponse {
        var query = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "30")
        ]
        if unreadOnly {
            query.append(URLQueryItem(name: "unread_only", value: "true"))
        }
        let response: StaffNotificationListResponse = try await send(
            APIEndpoint(method: .get, path: "staff/notifications", queryItems: query)
        )
        return response
    }

    func markStaffNotificationRead(id: String) async throws -> StaffNotificationReadResponse {
        let response: StaffNotificationReadResponse = try await send(
            APIEndpoint(method: .patch, path: "staff/notifications/\(id)/read")
        )
        return response
    }

    func markAllStaffNotificationsRead() async throws {
        struct MarkAllResponse: Decodable {
            let updatedCount: Int
        }
        let _: MarkAllResponse = try await send(
            APIEndpoint(method: .post, path: "staff/notifications/mark_all_read")
        )
    }

    func updateHandling(
        patientId: String,
        entryId: String,
        status: HandlingStatus,
        note: String?,
        callbackAt: Date? = nil
    ) async throws -> HandlingUpdateResponse {
        let body = try encodedBody(HandlingUpdateRequest(handlingStatus: status, note: note.nilIfEmpty, callbackAt: callbackAt))
        let response: HandlingUpdateResponse = try await send(APIEndpoint(method: .patch, path: "staff/patients/\(patientId)/timeline/\(entryId)/handling", body: body))
        return response
    }

    func askHotlineText(patientId: String?, text: String) async throws -> HotlineQuestionResponse {
        let request = HotlineQuestionTextRequest(mode: "text", patientId: patientId, text: text, clientRequestId: UUID().uuidString)
        let response: HotlineQuestionResponse = try await send(APIEndpoint(method: .post, path: "hotline/questions", body: try encodedBody(request)))
        return response
    }

    func askHotlineVoice(
        patientId: String?,
        audioURL: URL,
        duration: TimeInterval?,
        clientRequestId: String = UUID().uuidString
    ) async throws -> HotlineQuestionResponse {
        let audioData = try Data(contentsOf: audioURL)
        return try await askHotlineVoice(
            patientId: patientId,
            audioData: audioData,
            fileName: audioURL.lastPathComponent,
            mimeType: audioURL.uploadMimeType,
            duration: duration,
            clientRequestId: clientRequestId
        )
    }

    func askHotlineVoice(
        patientId: String?,
        audioData: Data,
        fileName: String,
        mimeType: String,
        duration: TimeInterval?,
        clientRequestId: String
    ) async throws -> HotlineQuestionResponse {
        try UploadLimits.validateAudio(data: audioData, fileName: fileName)
        var fields = [
            "mode": "voice",
            "client_request_id": clientRequestId
        ]
        if let patientId {
            fields["patient_id"] = patientId
        }
        if let duration {
            fields["recorded_duration_seconds"] = String(Int(duration.rounded()))
        }
        let file = MultipartFile(fieldName: "audio_file", fileName: fileName, mimeType: mimeType, data: audioData)
        let response: HotlineQuestionResponse = try await upload(path: "hotline/questions", fields: fields, files: [file])
        return response
    }

    func hotlineQuestion(id: String) async throws -> HotlineQuestionStatusResponse {
        let response: HotlineQuestionStatusResponse = try await send(APIEndpoint(method: .get, path: "hotline/questions/\(id)"))
        return response
    }

    func hotlineHistory(patientId: String? = nil, cursor: String? = nil) async throws -> HotlineHistoryResponse {
        var query = [URLQueryItem(name: "limit", value: "30")]
        if let patientId { query.append(URLQueryItem(name: "patient_id", value: patientId)) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response: HotlineHistoryResponse = try await send(APIEndpoint(method: .get, path: "hotline/questions", queryItems: query))
        return response
    }

    func registerDevice(
        role: UserRole,
        notificationChannel: NotificationChannel = .local,
        apnsToken: String? = nil
    ) async throws -> DeviceRegistrationResponse {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let osVersion = await MainActor.run {
            UIDevice.current.systemVersion
        }
        let request = DeviceRegistrationRequest(
            deviceId: DeviceIdentity.deviceID,
            deviceToken: apnsToken,
            platform: "ios",
            pushEnvironment: notificationChannel == .apns ? .sandbox : nil,
            notificationChannel: notificationChannel,
            role: role,
            appVersion: appVersion,
            osVersion: osVersion,
            locale: Locale.current.identifier
        )
        let response: DeviceRegistrationResponse = try await send(APIEndpoint(method: .post, path: "devices/register", body: try encodedBody(request)))
        return response
    }

    func deleteDevice() async throws {
        try await sendEmpty(APIEndpoint(method: .delete, path: "devices/\(DeviceIdentity.deviceID)"))
    }

    func notificationPreferences() async throws -> NotificationPreferencesResponse {
        let response: NotificationPreferencesResponse = try await send(APIEndpoint(method: .get, path: "devices/\(DeviceIdentity.deviceID)/notification_preferences"))
        return response
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferencesResponse {
        let request = NotificationPreferencesUpdateRequest(
            checkinRemindersEnabled: preferences.checkinRemindersEnabled,
            medicationRemindersEnabled: preferences.medicationRemindersEnabled,
            appointmentRemindersEnabled: preferences.appointmentRemindersEnabled,
            criticalStaffAlertsEnabled: preferences.criticalStaffAlertsEnabled
        )
        let response: NotificationPreferencesResponse = try await send(APIEndpoint(method: .patch, path: "devices/\(DeviceIdentity.deviceID)/notification_preferences", body: try encodedBody(request)))
        return response
    }

    func recordMedicationAdherence(medicationId: String, slot: String, taken: Bool) async throws -> MedicationAdherenceResponse {
        let request = MedicationAdherenceRequest(
            medicationId: medicationId,
            slot: slot,
            taken: taken,
            recordedVia: "voice",
            clientRequestId: UUID().uuidString
        )
        let response: MedicationAdherenceResponse = try await send(
            APIEndpoint(method: .post, path: "me/medications/adherence", body: try encodedBody(request))
        )
        return response
    }
}

private extension String {
    var trimmedLeadingSlash: String {
        while hasPrefix("/") {
            return String(dropFirst()).trimmedLeadingSlash
        }
        return self
    }

    var trimmedTrailingSlash: String {
        while hasSuffix("/") {
            return String(dropLast()).trimmedTrailingSlash
        }
        return self
    }

    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        switch self {
        case .some(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        case .none:
            return nil
        }
    }
}

nonisolated enum DeviceIdentity {
    static var deviceID: String {
        if let stored = UserDefaults.standard.string(forKey: AppConstants.deviceIDKey) {
            return stored
        }
        let newValue = UUID().uuidString
        UserDefaults.standard.set(newValue, forKey: AppConstants.deviceIDKey)
        return newValue
    }
}
