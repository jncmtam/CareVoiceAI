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
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-checkin", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleMedicationReminder(
        id: String,
        title: String,
        dateComponents: DateComponents,
        medicationId: String? = nil,
        slot: String? = nil
    ) {
        cancelReminder(identifier: "medication-\(id)")
        let content = UNMutableNotificationContent()
        content.title = L10n.text("notification.medication.title")
        content.body = title
        content.categoryIdentifier = "medication_reminder"
        if let medicationId {
            content.userInfo["medication_id"] = medicationId
        }
        if let slot {
            content.userInfo["slot"] = slot
        }
        let request = UNNotificationRequest(
            identifier: "medication-\(id)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        )
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleStaffRiskChangeNotification(patientName: String, patientId: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.text("notification.staff.risk_change.title")
        content.body = String(format: L10n.text("notification.staff.risk_change.body"), patientName, message)
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive
        content.userInfo["patient_id"] = patientId
        content.userInfo["notification_type"] = "risk_change"
        let request = UNNotificationRequest(
            identifier: "staff-risk-change-\(patientId)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleCriticalStaffAlert(count: Int, patientId: String? = nil, patientName: String? = nil) {
        cancelReminder(identifier: "staff-critical-alert")
        let content = UNMutableNotificationContent()
        content.title = L10n.text("notification.staff.critical.title")
        if let patientName {
            content.body = String(format: L10n.text("notification.staff.critical.body_named"), patientName)
        } else {
            content.body = String(format: L10n.text("notification.staff.critical.body"), count)
        }
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive
        if let patientId {
            content.userInfo["patient_id"] = patientId
        }
        let request = UNNotificationRequest(
            identifier: "staff-critical-alert",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static let appointmentReminderLeadDays = [3, 1]
    nonisolated private static let appointmentReminderHour = 8

    func syncAppointmentReminders(appointments: [Appointment], enabled: Bool) async {
        await cancelReminderGroup(prefix: "appointment-")
        guard enabled else { return }

        let upcoming = appointments
            .filter { ($0.status ?? "scheduled") == "scheduled" }
            .filter { $0.appointmentAt > Date() }
            .sorted { $0.appointmentAt < $1.appointmentAt }

        for appointment in upcoming {
            scheduleAppointmentReminder(for: appointment)
        }
    }

    func scheduleAppointmentReminder(for appointment: Appointment) {
        guard (appointment.status ?? "scheduled") == "scheduled" else { return }
        for leadDays in Self.appointmentReminderLeadDays {
            scheduleAppointmentReminderSlot(for: appointment, leadDays: leadDays)
        }
    }

    private func scheduleAppointmentReminderSlot(for appointment: Appointment, leadDays: Int) {
        let identifier = "appointment-\(appointment.id)-\(leadDays)d"
        cancelReminder(identifier: identifier)
        guard let triggerDate = Self.appointmentReminderTriggerDate(
            for: appointment.appointmentAt,
            leadDays: leadDays
        ) else { return }

        let content = UNMutableNotificationContent()
        content.title = Self.appointmentReminderTitle(leadDays: leadDays)
        content.body = Self.appointmentReminderBody(for: appointment, leadDays: leadDays)
        content.userInfo["appointment_id"] = appointment.id
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func appointmentReminderTitle(leadDays: Int) -> String {
        leadDays == 1
            ? L10n.text("notification.appointment.title_soon")
            : L10n.text("notification.appointment.title")
    }

    private static func appointmentReminderTriggerDate(
        for appointmentDate: Date,
        leadDays: Int,
        hour: Int = appointmentReminderHour
    ) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        guard appointmentDate > now else { return nil }

        guard let leadDay = calendar.date(byAdding: .day, value: -leadDays, to: appointmentDate) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: leadDay)
        components.hour = hour
        components.minute = 0
        guard var trigger = calendar.date(from: components) else { return nil }

        if trigger <= now {
            let startOfToday = calendar.startOfDay(for: now)
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return nil }
            var tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            tomorrowComponents.hour = hour
            tomorrowComponents.minute = 0
            guard let tomorrowTrigger = calendar.date(from: tomorrowComponents),
                  tomorrowTrigger < appointmentDate else {
                return nil
            }
            trigger = tomorrowTrigger
        }

        return trigger < appointmentDate ? trigger : nil
    }

    private static func appointmentReminderBody(for appointment: Appointment, leadDays: Int) -> String {
        let dateText = DateFormatters.shortDateTime.string(from: appointment.appointmentAt)
        let prefix = leadDays == 1 ? "notification.appointment.body_soon_" : "notification.appointment.body_"
        if let department = appointment.department, let doctor = appointment.doctorName {
            return String(format: L10n.text("\(prefix)detail"), dateText, department, doctor)
        }
        if let department = appointment.department {
            return String(format: L10n.text("\(prefix)department"), dateText, department)
        }
        return String(format: L10n.text("\(prefix)date"), dateText)
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.identifier == "staff-critical-alert" {
            await MainActor.run {
                HapticsManager.critical()
                HapticsManager.playStaffCriticalAlertSound()
            }
            return [.banner, .sound, .list]
        }
        return [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            if response.notification.request.identifier == "staff-critical-alert" {
                HapticsManager.critical()
                return
            }
            if response.notification.request.identifier.hasPrefix("medication-"),
               let medicationId = userInfo["medication_id"] as? String,
               let slot = userInfo["slot"] as? String {
                PatientNavigationCoordinator.shared.openMedicationAdherence(medicationId: medicationId, slot: slot)
            }
        }
    }
}
