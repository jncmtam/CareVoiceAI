import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceRegistration: DeviceRegistrationResponse?
    @Published private(set) var registrationError: String?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestPermissionAtValueMoment() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            registrationError = error.localizedDescription
            return false
        }
    }

    func updateDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02.2hhx", $0) }.joined()
        if let role = SessionManager.shared.currentRole {
            Task {
                await registerAPNSTokenIfPossible(token: token, role: role)
            }
        }
    }

    func updateRegistrationError(_ error: Error) {
        registrationError = error.localizedDescription
    }

    func registerCurrentDeviceIfPossible(role: UserRole) async {
        do {
            let response = try await APIClient.shared.registerDevice(role: role, notificationChannel: .local)
            deviceRegistration = response
            registrationError = nil
        } catch {
            registrationError = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }

    func applyLocalNotificationPreferences(_ preferences: NotificationPreferences) async {
        await refreshAuthorizationStatus()
        guard hasNotificationPermission else { return }

        if preferences.checkinRemindersEnabled {
            scheduleCheckinReminder()
        } else {
            cancelReminder(identifier: "daily-checkin")
        }

        if !preferences.medicationRemindersEnabled {
            await cancelReminderGroup(prefix: "medication-")
        }

        if !preferences.appointmentRemindersEnabled {
            await cancelReminderGroup(prefix: "appointment-")
        }
    }

    func scheduleCheckinReminder(hour: Int = 8, minute: Int = 0) {
        cancelReminder(identifier: "daily-checkin")
        let content = UNMutableNotificationContent()
        content.title = L10n.text("notification.checkin.title")
        content.body = L10n.text("notification.checkin.body")
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-checkin", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleMedicationReminder(id: String, title: String, dateComponents: DateComponents) {
        cancelReminder(identifier: "medication-\(id)")
        let content = UNMutableNotificationContent()
        content.title = L10n.text("notification.medication.title")
        content.body = title
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "medication-\(id)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        )
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleAppointmentReminder(id: String, date: Date) {
        cancelReminder(identifier: "appointment-\(id)")
        let content = UNMutableNotificationContent()
        content.title = L10n.text("notification.appointment.title")
        content.body = L10n.text("notification.appointment.body")
        content.sound = .default
        let triggerDate = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let request = UNNotificationRequest(
            identifier: "appointment-\(id)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private var hasNotificationPermission: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func registerAPNSTokenIfPossible(token: String, role: UserRole) async {
        do {
            let response = try await APIClient.shared.registerDevice(
                role: role,
                notificationChannel: .apns,
                apnsToken: token
            )
            deviceRegistration = response
            registrationError = nil
        } catch {
            registrationError = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }

    private func cancelReminder(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func cancelReminderGroup(prefix: String) async {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
