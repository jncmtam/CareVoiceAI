import Foundation
import UIKit

nonisolated final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    private let session: URLSession
    private let tokenStore: TokenStore

    var baseURL: URL {
        let configured = UserDefaults.standard.string(forKey: AppConstants.apiBaseURLKey)
            ?? Bundle.main.object(forInfoDictionaryKey: "CAREVOICE_API_BASE_URL") as? String
            ?? AppConstants.defaultBaseURL
        return URL(string: configured) ?? URL(string: AppConstants.defaultBaseURL)!
    }

    init(session: URLSession = .shared, tokenStore: TokenStore = .shared) {
        self.session = session
        self.tokenStore = tokenStore
    }

    func send<Response: Decodable>(_ endpoint: APIEndpoint, requiresAuth: Bool = true) async throws -> Response {
        let request = try makeRequest(endpoint, requiresAuth: requiresAuth)
        let (data, response) = try await perform(request)
        return try decode(Response.self, from: data, response: response)
    }

    func sendEmpty(_ endpoint: APIEndpoint, requiresAuth: Bool = true) async throws {
        let request = try makeRequest(endpoint, requiresAuth: requiresAuth)
        let (data, response) = try await perform(request)
        _ = try validate(data: data, response: response)
    }

    func upload<Response: Decodable>(
        path: String,
        fields: [String: String],
        files: [MultipartFile],
        requiresAuth: Bool = true
    ) async throws -> Response {
        let builder = MultipartFormDataBuilder()
        let body = builder.build(fields: fields, files: files)
        let endpoint = APIEndpoint(
            method: .post,
            path: path,
            headers: ["Content-Type": builder.contentType],
            body: body
        )
        return try await send(endpoint, requiresAuth: requiresAuth)
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
                throw APIError.network(message: error.localizedDescription)
            }
        } catch {
            throw APIError.unknown(message: error.localizedDescription)
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
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.loginStaff(login: login, password: password)
        }
        let body = try encodedBody(StaffLoginRequest(login: login, password: password, deviceId: DeviceIdentity.deviceID))
        let response: AuthResponse = try await send(APIEndpoint(method: .post, path: "auth/staff/login", body: body), requiresAuth: false)
        return response
    }

    func requestPatientOTP(phoneNumber: String, patientCode: String?) async throws -> PatientOtpResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.requestPatientOTP(phoneNumber: phoneNumber, patientCode: patientCode)
        }
        let body = try encodedBody(PatientOtpRequest(phoneNumber: phoneNumber, patientCode: patientCode.nilIfEmpty))
        let response: PatientOtpResponse = try await send(APIEndpoint(method: .post, path: "auth/patient/request_otp", body: body), requiresAuth: false)
        return response
    }

    func verifyPatientOTP(sessionId: String, code: String) async throws -> AuthResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.verifyPatientOTP(sessionId: sessionId, code: code)
        }
        let body = try encodedBody(PatientOtpVerifyRequest(otpSessionId: sessionId, otpCode: code, deviceId: DeviceIdentity.deviceID))
        let response: AuthResponse = try await send(APIEndpoint(method: .post, path: "auth/patient/verify_otp", body: body), requiresAuth: false)
        return response
    }

    func loginPatientCode(patientCode: String, phoneLast4: String) async throws -> AuthResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.loginPatientCode(patientCode: patientCode, phoneLast4: phoneLast4)
        }
        let body = try encodedBody(PatientCodeLoginRequest(patientCode: patientCode, phoneLast4: phoneLast4, deviceId: DeviceIdentity.deviceID))
        let response: AuthResponse = try await send(APIEndpoint(method: .post, path: "auth/patient/login_code", body: body), requiresAuth: false)
        return response
    }

    func refreshToken(_ refreshToken: String) async throws -> RefreshTokenResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.refreshToken(refreshToken)
        }
        let body = try encodedBody(RefreshTokenRequest(refreshToken: refreshToken))
        let response: RefreshTokenResponse = try await send(APIEndpoint(method: .post, path: "auth/refresh", body: body), requiresAuth: false)
        return response
    }

    func logout(refreshToken: String?) async throws {
        if AppConstants.isDemoMode {
            try await DemoAPIService.shared.logout(refreshToken: refreshToken)
            return
        }
        let body = try encodedBody(LogoutRequest(deviceId: DeviceIdentity.deviceID, refreshToken: refreshToken))
        try await sendEmpty(APIEndpoint(method: .post, path: "auth/logout", body: body))
    }

    func me() async throws -> CurrentUserResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.me()
        }
        let response: CurrentUserResponse = try await send(APIEndpoint(method: .get, path: "me"))
        return response
    }

    func createPatient(_ request: PatientCreateRequest) async throws -> PatientResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.createPatient(request)
        }
        let response: PatientResponse = try await send(APIEndpoint(method: .post, path: "patients", body: try encodedBody(request)))
        return response
    }

    func patient(id: String) async throws -> PatientResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.patient(id: id)
        }
        let response: PatientResponse = try await send(APIEndpoint(method: .get, path: "patients/\(id)"))
        return response
    }

    func myPatientProfile() async throws -> PatientResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.myPatientProfile()
        }
        let response: PatientResponse = try await send(APIEndpoint(method: .get, path: "me/patient"))
        return response
    }

    func myMedications() async throws -> MedicationListResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.myMedications()
        }
        let response: MedicationListResponse = try await send(APIEndpoint(method: .get, path: "me/medications"))
        return response
    }

    func medications(patientId: String) async throws -> MedicationListResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.medications(patientId: patientId)
        }
        let response: MedicationListResponse = try await send(APIEndpoint(method: .get, path: "patients/\(patientId)/medications"))
        return response
    }

    func myAppointments() async throws -> AppointmentListResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.myAppointments()
        }
        let response: AppointmentListResponse = try await send(APIEndpoint(method: .get, path: "me/appointments"))
        return response
    }

    func uploadDocument(patientId: String, documentType: DocumentType, mode: OcrMode, fileURL: URL) async throws -> DocumentUploadResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.uploadDocument(patientId: patientId, documentType: documentType, mode: mode, fileURL: fileURL)
        }
        let data = try Data(contentsOf: fileURL)
        let file = MultipartFile(fieldName: "file", fileName: fileURL.lastPathComponent, mimeType: fileURL.inferredMimeType, data: data)
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
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.ocrJob(id: id)
        }
        let response: OCRJobResponse = try await send(APIEndpoint(method: .get, path: "ocr/jobs/\(id)"))
        return response
    }

    func cancelOCRJob(id: String, reason: String) async throws -> CancelJobResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.cancelOCRJob(id: id, reason: reason)
        }
        let response: CancelJobResponse = try await send(APIEndpoint(method: .post, path: "ocr/jobs/\(id)/cancel", body: try encodedBody(CancelJobRequest(reason: reason))))
        return response
    }

    func confirmOCR(patientId: String, uploadId: String, request: OCRConfirmRequest) async throws -> OCRConfirmResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.confirmOCR(patientId: patientId, uploadId: uploadId, request: request)
        }
        let response: OCRConfirmResponse = try await send(APIEndpoint(method: .post, path: "patients/\(patientId)/documents/\(uploadId)/confirm_ocr", body: try encodedBody(request)))
        return response
    }

    func todayCheckin() async throws -> TodayCheckinResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.todayCheckin()
        }
        let response: TodayCheckinResponse = try await send(APIEndpoint(method: .get, path: "me/checkins/today"))
        return response
    }

    func checkinAudio(checkinId: String) async throws -> CheckinAudioStatusResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.checkinAudio(checkinId: checkinId)
        }
        let response: CheckinAudioStatusResponse = try await send(APIEndpoint(method: .get, path: "checkins/\(checkinId)/audio"))
        return response
    }

    func submitCheckin(checkinId: String, audioURL: URL?, quickAnswerId: String?, duration: TimeInterval?) async throws -> SubmitCheckinResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.submitCheckin(checkinId: checkinId, audioURL: audioURL, quickAnswerId: quickAnswerId, duration: duration)
        }
        var fields = [
            "client_recorded_at": ISO8601DateFormatter().string(from: Date()),
            "client_request_id": UUID().uuidString
        ]
        if let quickAnswerId {
            fields["quick_answer_id"] = quickAnswerId
        }
        if let duration {
            fields["recorded_duration_seconds"] = String(Int(duration.rounded()))
        }
        var files: [MultipartFile] = []
        if let audioURL {
            files.append(MultipartFile(fieldName: "audio_file", fileName: audioURL.lastPathComponent, mimeType: audioURL.inferredMimeType, data: try Data(contentsOf: audioURL)))
        }
        let response: SubmitCheckinResponse = try await upload(path: "checkins/\(checkinId)/responses", fields: fields, files: files)
        return response
    }

    func checkinJob(id: String) async throws -> CheckinJobResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.checkinJob(id: id)
        }
        let response: CheckinJobResponse = try await send(APIEndpoint(method: .get, path: "checkin_jobs/\(id)"))
        return response
    }

    func checkinHistory(cursor: String? = nil) async throws -> CheckinHistoryResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.checkinHistory(cursor: cursor)
        }
        var query = [URLQueryItem(name: "limit", value: "30")]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: CheckinHistoryResponse = try await send(APIEndpoint(method: .get, path: "me/checkins/history", queryItems: query))
        return response
    }

    func dashboardOverview() async throws -> DashboardOverview {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.dashboardOverview()
        }
        let response: DashboardOverview = try await send(APIEndpoint(method: .get, path: "staff/dashboard/overview"))
        return response
    }

    func priorityPatients(page: Int = 1, query: String? = nil, riskLevel: RiskLevel? = nil) async throws -> PriorityPatientListResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.priorityPatients(page: page, query: query, riskLevel: riskLevel)
        }
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
        let response: PriorityPatientListResponse = try await send(APIEndpoint(method: .get, path: "staff/patients/priority", queryItems: items))
        return response
    }

    func patientTimeline(patientId: String, cursor: String? = nil) async throws -> PatientTimelineResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.patientTimeline(patientId: patientId, cursor: cursor)
        }
        var query = [URLQueryItem(name: "limit", value: "40")]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: PatientTimelineResponse = try await send(APIEndpoint(method: .get, path: "staff/patients/\(patientId)/timeline", queryItems: query))
        return response
    }

    func updateHandling(patientId: String, entryId: String, status: HandlingStatus, note: String?) async throws -> HandlingUpdateResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.updateHandling(patientId: patientId, entryId: entryId, status: status, note: note)
        }
        let body = try encodedBody(HandlingUpdateRequest(handlingStatus: status, note: note.nilIfEmpty, callbackAt: status == .calledBack ? Date() : nil))
        let response: HandlingUpdateResponse = try await send(APIEndpoint(method: .patch, path: "staff/patients/\(patientId)/timeline/\(entryId)/handling", body: body))
        return response
    }

    func askHotlineText(patientId: String?, text: String) async throws -> HotlineQuestionResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.askHotlineText(patientId: patientId, text: text)
        }
        let request = HotlineQuestionTextRequest(mode: "text", patientId: patientId, text: text, clientRequestId: UUID().uuidString)
        let response: HotlineQuestionResponse = try await send(APIEndpoint(method: .post, path: "hotline/questions", body: try encodedBody(request)))
        return response
    }

    func askHotlineVoice(patientId: String?, audioURL: URL, duration: TimeInterval?) async throws -> HotlineQuestionResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.askHotlineVoice(patientId: patientId, audioURL: audioURL, duration: duration)
        }
        var fields = [
            "mode": "voice",
            "client_request_id": UUID().uuidString
        ]
        if let patientId {
            fields["patient_id"] = patientId
        }
        if let duration {
            fields["recorded_duration_seconds"] = String(Int(duration.rounded()))
        }
        let file = MultipartFile(fieldName: "audio_file", fileName: audioURL.lastPathComponent, mimeType: audioURL.inferredMimeType, data: try Data(contentsOf: audioURL))
        let response: HotlineQuestionResponse = try await upload(path: "hotline/questions", fields: fields, files: [file])
        return response
    }

    func hotlineQuestion(id: String) async throws -> HotlineQuestionStatusResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.hotlineQuestion(id: id)
        }
        let response: HotlineQuestionStatusResponse = try await send(APIEndpoint(method: .get, path: "hotline/questions/\(id)"))
        return response
    }

    func hotlineHistory(patientId: String? = nil, cursor: String? = nil) async throws -> HotlineHistoryResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.hotlineHistory(patientId: patientId, cursor: cursor)
        }
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
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.registerDevice(role: role, notificationChannel: notificationChannel)
        }
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
        if AppConstants.isDemoMode {
            try await DemoAPIService.shared.deleteDevice()
            return
        }
        try await sendEmpty(APIEndpoint(method: .delete, path: "devices/\(DeviceIdentity.deviceID)"))
    }

    func notificationPreferences() async throws -> NotificationPreferencesResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.notificationPreferences()
        }
        let response: NotificationPreferencesResponse = try await send(APIEndpoint(method: .get, path: "devices/\(DeviceIdentity.deviceID)/notification_preferences"))
        return response
    }

    func updateNotificationPreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferencesResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.updateNotificationPreferences(preferences)
        }
        let request = NotificationPreferencesUpdateRequest(
            checkinRemindersEnabled: preferences.checkinRemindersEnabled,
            medicationRemindersEnabled: preferences.medicationRemindersEnabled,
            appointmentRemindersEnabled: preferences.appointmentRemindersEnabled,
            criticalStaffAlertsEnabled: preferences.criticalStaffAlertsEnabled
        )
        let response: NotificationPreferencesResponse = try await send(APIEndpoint(method: .patch, path: "devices/\(DeviceIdentity.deviceID)/notification_preferences", body: try encodedBody(request)))
        return response
    }

    func createFaceVerificationSession(patientId: String) async throws -> FaceVerificationSessionResponse {
        if AppConstants.isDemoMode {
            return try await DemoAPIService.shared.createFaceVerificationSession(patientId: patientId)
        }
        let request = FaceVerificationSessionRequest(patientId: patientId, purpose: "follow_up_visit")
        let response: FaceVerificationSessionResponse = try await send(APIEndpoint(method: .post, path: "identity/face_verification/sessions", body: try encodedBody(request)))
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

private extension URL {
    var inferredMimeType: String {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "pdf":
            return "application/pdf"
        case "wav":
            return "audio/wav"
        case "m4a", "aac":
            return "audio/mp4"
        default:
            return "application/octet-stream"
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
