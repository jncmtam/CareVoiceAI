import Foundation

struct DashboardOverview: Decodable {
    let totalActivePatients: Int
    let needsAttentionToday: Int
    let needsInterventionToday: Int
    let checkinCompletionRate: Double
    let pendingOcrJobs: Int?
    let pendingAnalysisJobs: Int?
    let updatedAt: Date?
}

struct PriorityPatientListResponse: Decodable {
    let items: [PatientSummary]
    let page: Int
    let perPage: Int
    let total: Int
    let hasNext: Bool
}

struct PatientTimelineResponse: Decodable {
    let patient: TimelinePatientHeader
    let items: [TimelineEntry]
    let nextCursor: String?
}

struct TimelinePatientHeader: Codable, Identifiable {
    let id: String
    let patientCode: String
    let fullName: String
    let age: Int?
    let latestRiskLevel: RiskLevel?
}

struct TimelineEntry: Codable, Identifiable {
    let id: String
    let type: TimelineEntryType
    let occurredAt: Date
    let status: JobStatus
    let riskLevel: RiskLevel?
    let summary: String?
    let transcript: String?
    let riskReasons: [String]?
    let handlingStatus: HandlingStatus?
    let staffAlertId: String?
    let displayMessage: String?
    let jobId: String?
}

struct HandlingUpdateRequest: Encodable {
    let handlingStatus: HandlingStatus
    let note: String?
    let callbackAt: Date?
}

struct HandlingUpdateResponse: Decodable {
    let entryId: String
    let handlingStatus: HandlingStatus
    let handledBy: HandledByUser?
    let handledAt: Date?
    let note: String?
}

struct HandledByUser: Codable, Identifiable {
    let id: String
    let fullName: String
}
