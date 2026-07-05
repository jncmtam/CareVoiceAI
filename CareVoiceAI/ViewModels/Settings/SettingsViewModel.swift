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
    @Published var apiBaseURL = APIClient.shared.baseURL.absoluteString
    @Published var error: APIError?
    @Published var saveSuccessMessage: String?

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
        saveSuccessMessage = nil
        apiBaseURL = apiClient.baseURL.absoluteString
        do {
            preferences = try await apiClient.notificationPreferences().preferences
        } catch {
            self.error = APIError.from(error)
        }
    }

    func requestNotifications() async {
        let granted = await NotificationManager.shared.requestPermissionAtValueMoment()
        if granted, let role = session.currentRole {
            await NotificationManager.shared.registerCurrentDeviceIfPossible(role: role)
            await NotificationManager.shared.applyLocalNotificationPreferences(preferences)
            if preferences.appointmentRemindersEnabled,
               let appointments = try? await apiClient.myAppointments().appointments {
                await NotificationManager.shared.syncAppointmentReminders(appointments: appointments, enabled: true)
            }
        }
    }

    func savePreferences(isStaff: Bool) async {
        isSaving = true
        error = nil
        saveSuccessMessage = nil
        defer { isSaving = false }
        do {
            let response = try await apiClient.updateNotificationPreferences(preferences)
            preferences = response.preferences
            await NotificationManager.shared.applyLocalNotificationPreferences(response.preferences)
            if response.preferences.appointmentRemindersEnabled,
               let appointments = try? await apiClient.myAppointments().appointments {
                await NotificationManager.shared.syncAppointmentReminders(appointments: appointments, enabled: true)
            }
            saveSuccessMessage = notificationSaveSummary(for: response.preferences, isStaff: isStaff)
            HapticsManager.success()
        } catch {
            self.error = APIError.from(error)
        }
    }

    private func notificationSaveSummary(for preferences: NotificationPreferences, isStaff: Bool) -> String {
        var enabledItems: [String] = []
        if preferences.checkinRemindersEnabled {
            enabledItems.append(L10n.text("settings.checkin_reminders"))
        }
        if preferences.medicationRemindersEnabled {
            enabledItems.append(L10n.text("settings.medication_reminders"))
        }
        if preferences.appointmentRemindersEnabled {
            enabledItems.append(L10n.text("settings.appointment_reminders"))
        }
        if isStaff, preferences.criticalStaffAlertsEnabled {
            enabledItems.append(L10n.text("settings.critical_alerts"))
        }
        if enabledItems.isEmpty {
            return L10n.text("settings.notifications_saved_none")
        }
        return String(
            format: L10n.text("settings.notifications_saved_active"),
            enabledItems.joined(separator: ", ")
        )
    }

    func logout() async {
        await session.logout()
    }

    func changeRole() async {
        await session.clearRoleAndLogout()
    }
}
