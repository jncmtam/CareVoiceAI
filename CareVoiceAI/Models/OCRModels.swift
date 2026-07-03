import Foundation

struct DocumentUploadResponse: Decodable {
    let uploadId: String
    let jobId: String
    let status: JobStatus
    let pollAfterSeconds: Double?
    let message: String?
}

struct OCRJobResponse: Decodable {
    let jobId: String
    let uploadId: String?
    let patientId: String?
    let status: JobStatus
    let progress: Int?
    let stage: String?
    let pollAfterSeconds: Double?
    let createdAt: Date?
    let updatedAt: Date?
    let rawText: String?
    let draftMedications: [OCRDraftMedication]?
    let draftFollowUp: FollowUpDraft?
    let warnings: [String]?
}

struct OCRDraftMedication: Codable, Identifiable {
    var id = UUID()
    var name: String
    var strength: String?
    var dosage: String?
    var frequency: String?
    var timesOfDay: [MedicationTimeOfDay]?
    var instructions: String?
    var confidence: Double?

    private enum CodingKeys: String, CodingKey {
        case name
        case strength
        case dosage
        case frequency
        case timesOfDay
        case instructions
        case confidence
    }
}

struct OCRConfirmRequest: Encodable {
    let jobId: String
    let confirmedByUserId: String?
    let medications: [Medication]
    let followUp: FollowUpDraft?
    let nurseNote: String?
}

struct OCRConfirmResponse: Decodable {
    let document: MedicalDocument
    let medications: [Medication]
}

struct CancelJobRequest: Encodable {
    let reason: String
}

struct CancelJobResponse: Decodable {
    let jobId: String
    let status: JobStatus
}
