import Foundation
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published private(set) var currentUser: AppUser?
    @Published private(set) var patientContext: PatientSessionContext?
    @Published private(set) var isRestoring = false
    @Published var authError: APIError?

    private let apiClient: APIClient
    private let tokenStore: TokenStore

    private init(apiClient: APIClient = .shared, tokenStore: TokenStore = .shared) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
    }

    var isAuthenticated: Bool {
        currentUser != nil && tokenStore.accessToken != nil
    }

    var currentRole: UserRole? {
        currentUser?.role ?? selectedRole
    }

    var selectedRole: UserRole? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: AppConstants.selectedRoleKey) else {
                return nil
            }
            return UserRole(rawValue: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: AppConstants.selectedRoleKey)
        }
    }

    func chooseRole(_ role: UserRole) {
        selectedRole = role
    }

    func restoreSession() async {
        guard tokenStore.accessToken != nil else {
            return
        }
        isRestoring = true
        defer { isRestoring = false }
        do {
            let response = try await apiClient.me()
            apply(user: response.user, patient: response.patient)
        } catch {
            tokenStore.clear()
            currentUser = nil
            patientContext = nil
            authError = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func loginStaff(login: String, password: String) async throws {
        let response = try await apiClient.loginStaff(login: login, password: password)
        completeLogin(response)
    }

    func requestPatientOTP(phoneNumber: String, patientCode: String?) async throws -> PatientOtpResponse {
        try await apiClient.requestPatientOTP(phoneNumber: phoneNumber, patientCode: patientCode)
    }

    func verifyPatientOTP(sessionId: String, code: String) async throws {
        let response = try await apiClient.verifyPatientOTP(sessionId: sessionId, code: code)
        completeLogin(response)
    }

    func loginPatientWithCode(patientCode: String, phoneLast4: String) async throws {
        let response = try await apiClient.loginPatientCode(patientCode: patientCode, phoneLast4: phoneLast4)
        completeLogin(response)
    }

    func logout() async {
        let refreshToken = tokenStore.refreshToken
        do {
            try await apiClient.logout(refreshToken: refreshToken)
            try? await apiClient.deleteDevice()
        } catch {
            authError = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
        tokenStore.clear()
        currentUser = nil
        patientContext = nil
    }

    func clearRoleAndLogout() async {
        await logout()
        selectedRole = nil
    }

    private func completeLogin(_ response: AuthResponse) {
        tokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        apply(user: response.user, patient: response.patient)
        selectedRole = response.user.role
        Task {
            await NotificationManager.shared.registerCurrentDeviceIfPossible(role: response.user.role)
        }
    }

    private func apply(user: AppUser, patient: PatientSessionContext?) {
        currentUser = user
        patientContext = patient
        selectedRole = user.role
    }
}
