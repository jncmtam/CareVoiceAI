import Foundation

enum UserRole: String, Codable {
    case patient
    case caregiver
    case nurse
    case doctor
    case admin
}

enum RiskLevel: String, Codable, CaseIterable {
    case normal
    case attention
    case intervention
}

enum JobStatus: String, Codable {
    case queued
    case uploading
    case processing
    case transcribing
    case analyzing
    case summarizing
    case needsReview = "needs_review"
    case completed
    case failed
    case cancelled
    case expired

    var isTerminal: Bool {
        switch self {
        case .needsReview, .completed, .failed, .cancelled, .expired:
            return true
        default:
            return false
        }
    }
}

enum AudioStatus: String, Codable {
    case ready
    case generating
    case unavailable
    case failed
}

enum DocumentType: String, Codable {
    case prescription
    case dischargeNote = "discharge_note"
}

enum OcrMode: String, Codable {
    case auto
    case basic
    case table
}

enum HandlingStatus: String, Codable {
    case new
    case viewed
    case calledBack = "called_back"
    case resolved
}

enum TimelineEntryType: String, Codable {
    case checkinResponse = "checkin_response"
    case hotlineQuestion = "hotline_question"
    case medicationUpdate = "medication_update"
    case appointment
}

enum PushEnvironment: String, Codable {
    case sandbox
    case production
}

enum NotificationChannel: String, Codable {
    case local
    case webPush = "web_push"
    case apns
}

enum Gender: String, Codable, CaseIterable {
    case male
    case female
    case other
}

enum MedicationTimeOfDay: String, Codable, CaseIterable {
    case morning
    case noon
    case afternoon
    case evening
    case bedtime
}

struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody
}

struct APIErrorBody: Decodable {
    let code: String
    let message: String
    let details: [String: String]?
    let traceId: String?
}

struct EmptyResponse: Decodable {}

enum LoadableState<Value> {
    case idle
    case loading(String)
    case loaded(Value)
    case empty(String)
    case failed(APIError)
}

struct PageQuery {
    var page: Int = 1
    var perPage: Int = 30
}

struct PaginatedResponse<Item: Codable>: Codable {
    let items: [Item]
    let page: Int?
    let perPage: Int?
    let total: Int?
    let hasNext: Bool?
    let nextCursor: String?
}
