import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var preferences = NotificationPreferences(
        checkinRemindersEnabled: true,
        medicationRemindersEnabled: true,
        appointmentRemindersEnabled: true,
        criticalStaffAlertsEnabled: true
    )
    @Published var isSaving = false
    @Published var isDemoMode = AppConstants.isDemoMode
    @Published var error: APIError?

    private let apiClient: APIClient
    private let session: SessionManager

    convenience init() {
        self.init(apiClient: .shared, session: .shared)
    }

    init(apiClient: APIClient, session: SessionManager) {
        self.apiClient = apiClient
        self.session = session
    }

    func loadPreferences() async {
        error = nil
        do {
            preferences = try await apiClient.notificationPreferences().preferences
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func requestNotifications() async {
        let granted = await NotificationManager.shared.requestPermissionAtValueMoment()
        if granted, let role = session.currentRole {
            await NotificationManager.shared.registerCurrentDeviceIfPossible(role: role)
            await NotificationManager.shared.applyLocalNotificationPreferences(preferences)
        }
    }

    func savePreferences() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let response = try await apiClient.updateNotificationPreferences(preferences)
            preferences = response.preferences
            await NotificationManager.shared.applyLocalNotificationPreferences(response.preferences)
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }

    func updateDemoMode(_ enabled: Bool) {
        AppConstants.isDemoMode = enabled
        isDemoMode = enabled
    }

    func logout() async {
        await session.logout()
    }

    func changeRole() async {
        await session.clearRoleAndLogout()
    }
}
