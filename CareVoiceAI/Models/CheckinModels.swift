import Foundation

struct TodayCheckinResponse: Decodable {
    let checkin: Checkin
}

struct Checkin: Codable, Identifiable {
    let id: String
    let patientId: String?
    let scheduledFor: String?
    let status: String
    let completedJobId: String?
    let questionText: String
    let audioStatus: AudioStatus
    let audioUrl: URL?
    let audioCacheKey: String?
    let ttsJobId: String?
    let pollAfterSeconds: Double?
    let quickAnswers: [QuickAnswer]
    let expiresAt: Date?
}

struct QuickAnswer: Codable, Identifiable {
    let id: String
    let label: String
}

struct CheckinAudioStatusResponse: Decodable {
    let checkinId: String
    let audioStatus: AudioStatus
    let audioUrl: URL?
    let audioCacheKey: String?
    let pollAfterSeconds: Double?
}

struct CheckinTranscribeResponse: Decodable {
    let transcript: String
    let suggestedRiskLevel: RiskLevel?
    let message: String?
}

struct SubmitCheckinResponse: Decodable {
    let responseId: String
    let jobId: String
    let status: JobStatus
    let pollAfterSeconds: Double?
    let message: String?
}

struct CheckinJobResponse: Decodable {
    let jobId: String
    let responseId: String?
    let status: JobStatus
    let progress: Int?
    let stage: String?
    let displayMessage: String?
    let pollAfterSeconds: Double?
    let transcript: String?
    let summary: String?
    let risk: RiskAssessment?
    let staffAlertId: String?
    let caregiverAlertSentAt: Date?
    let completedAt: Date?
}

struct RiskAssessment: Codable {
    let level: RiskLevel
    let label: String?
    let reasons: [String]?
    var analysisHints: [String]? = nil
    let needsStaffReview: Bool
}

struct CheckinHistoryItem: Codable, Identifiable {
    let id: String
    let checkedInAt: Date
    let status: String
    let riskLevel: RiskLevel?
    let patientMessage: String?
    let summaryForPatient: String?
    let staffNote: String?
}

struct CheckinHistoryResponse: Decodable {
    let items: [CheckinHistoryItem]
    let nextCursor: String?
}
