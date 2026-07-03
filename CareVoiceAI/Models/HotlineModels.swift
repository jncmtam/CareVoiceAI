import Foundation

struct HotlineQuestionTextRequest: Encodable {
    let mode: String
    let patientId: String?
    let text: String
    let clientRequestId: String
}

struct HotlineQuestionResponse: Decodable {
    let questionId: String
    let jobId: String?
    let status: JobStatus
    let answerText: String?
    let sourceScope: String?
    let needsStaffReview: Bool?
    let staffAlertId: String?
    let pollAfterSeconds: Double?
}

struct HotlineQuestionStatusResponse: Decodable {
    let questionId: String
    let status: JobStatus
    let transcript: String?
    let answerText: String?
    let needsStaffReview: Bool?
    let riskLevel: RiskLevel?
    let staffAlertId: String?
    let pollAfterSeconds: Double?
}

struct HotlineHistoryItem: Codable, Identifiable {
    var id: String { questionId }
    let questionId: String
    let askedAt: Date
    let questionText: String?
    let answerText: String?
    let needsStaffReview: Bool?
}

struct HotlineHistoryResponse: Decodable {
    let items: [HotlineHistoryItem]
    let nextCursor: String?
}
