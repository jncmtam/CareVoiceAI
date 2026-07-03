import Foundation

@MainActor
final class StaffLoginViewModel: ObservableObject {
    @Published var login = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var error: APIError?

    private let session: SessionManager

    convenience init() {
        self.init(session: .shared)
    }

    init(session: SessionManager) {
        self.session = session
    }

    var canSubmit: Bool {
        !login.cvTrimmed.isEmpty && !password.isEmpty
    }

    func submit() async {
        guard canSubmit else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await session.loginStaff(login: login.cvTrimmed, password: password)
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func submitDemo() async {
        login = "nurse01@hospital.vn"
        password = "demo123"
        await submit()
    }
}

@MainActor
final class PatientLoginViewModel: ObservableObject {
    enum Step {
        case enterPhone
        case enterOTP(sessionId: String, maskedPhone: String)
    }

    @Published var phoneNumber = ""
    @Published var patientCode = ""
    @Published var phoneLast4 = ""
    @Published var otpCode = ""
    @Published var step: Step = .enterPhone
    @Published var isLoading = false
    @Published var error: APIError?

    private let session: SessionManager

    convenience init() {
        self.init(session: .shared)
    }

    init(session: SessionManager) {
        self.session = session
    }

    func requestOTP() async {
        guard !phoneNumber.cvTrimmed.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await session.requestPatientOTP(phoneNumber: phoneNumber.cvTrimmed, patientCode: patientCode.cvNilIfEmpty)
            step = .enterOTP(sessionId: response.otpSessionId, maskedPhone: response.maskedPhoneNumber)
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func verifyOTP() async {
        guard case .enterOTP(let sessionId, _) = step, !otpCode.cvTrimmed.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await session.verifyPatientOTP(sessionId: sessionId, code: otpCode.cvTrimmed)
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func loginWithCode() async {
        guard !patientCode.cvTrimmed.isEmpty, !phoneLast4.cvTrimmed.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await session.loginPatientWithCode(patientCode: patientCode.cvTrimmed, phoneLast4: phoneLast4.cvTrimmed)
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func loginDemoPatient() async {
        patientCode = "BN-2026-0001"
        phoneLast4 = "4567"
        await loginWithCode()
    }
}
