import Foundation

struct MedicationAdherenceRequest: Encodable {
    let medicationId: String
    let slot: String
    let taken: Bool
    let recordedVia: String
    let clientRequestId: String?

    init(medicationId: String, slot: String, taken: Bool, recordedVia: String = "voice", clientRequestId: String? = nil) {
        self.medicationId = medicationId
        self.slot = slot
        self.taken = taken
        self.recordedVia = recordedVia
        self.clientRequestId = clientRequestId
    }
}

struct MedicationAdherenceResponse: Decodable {
    let medicationId: String
    let slot: String
    let taken: Bool
    let missedDosesToday: Int
    let message: String
}