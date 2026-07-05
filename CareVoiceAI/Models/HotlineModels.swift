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
    let transcript: String?
    let answerText: String?
    let sourceScope: String?
    let needsStaffReview: Bool?
    let riskLevel: RiskLevel?
    let reasons: [String]?
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
    let reasons: [String]?
    let staffAlertId: String?
    let pollAfterSeconds: Double?
}

struct HotlineHistoryItem: Codable, Identifiable {
    var id: String { questionId }
    let questionId: String
    let askedAt: Date
    let mode: String?
    let questionText: String?
    let transcript: String?
    let answerText: String?
    let needsStaffReview: Bool?
    let riskLevel: RiskLevel?
    let reasons: [String]?
}

struct HotlineHistoryResponse: Decodable {
    let items: [HotlineHistoryItem]
    let nextCursor: String?
}