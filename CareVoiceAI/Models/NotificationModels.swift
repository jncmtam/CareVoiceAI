import Foundation

struct DeviceRegistrationRequest: Encodable {
    let deviceId: String
    let deviceToken: String?
    let platform: String
    let pushEnvironment: PushEnvironment?
    let notificationChannel: NotificationChannel
    let role: UserRole
    let appVersion: String
    let osVersion: String
    let locale: String
}

struct DeviceRegistrationResponse: Decodable {
    let deviceId: String
    let registered: Bool
    let notificationChannel: NotificationChannel?
    let remotePushEnabled: Bool?
    let message: String?
    let updatedAt: Date?
}

struct NotificationPreferences: Codable {
    var checkinRemindersEnabled: Bool
    var medicationRemindersEnabled: Bool
    var appointmentRemindersEnabled: Bool
    var criticalStaffAlertsEnabled: Bool
}

struct NotificationPreferencesUpdateRequest: Encodable {
    let checkinRemindersEnabled: Bool
    let medicationRemindersEnabled: Bool
    let appointmentRemindersEnabled: Bool
    let criticalStaffAlertsEnabled: Bool
}

struct NotificationPreferencesResponse: Decodable {
    let deviceId: String
    let preferences: NotificationPreferences
}

struct FaceVerificationSessionRequest: Encodable {
    let patientId: String
    let purpose: String
}

struct FaceVerificationSessionResponse: Decodable {
    let sessionId: String
    let status: String
    let uploadUrl: URL?
    let expiresAt: Date?
}

struct FaceVerificationStatusResponse: Decodable {
    let sessionId: String
    let status: String
    let verifiedAt: Date?
    let needsStaffReview: Bool
}

struct FaceVerificationUploadResponse: Decodable {
    let sessionId: String
    let status: String
    let verifiedAt: Date?
    let needsStaffReview: Bool
    let message: String
}
