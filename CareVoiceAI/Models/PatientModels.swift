import Foundation

struct PatientCreateRequest: Encodable {
    var fullName: String
    var dateOfBirth: String?
    var gender: Gender?
    var phoneNumber: String
    var caregiverName: String?
    var caregiverPhoneNumber: String?
    var diagnoses: [String]
    var address: String?
    var primaryDoctorName: String?
    var notes: String?
}

struct PatientUpdateRequest: Encodable {
    var fullName: String?
    var phoneNumber: String?
    var caregiverName: String?
    var caregiverPhoneNumber: String?
    var notes: String?
}

struct PatientDeleteResponse: Decodable {
    let patientId: String
    let deleted: Bool
}

struct PatientResponse: Decodable {
    let patient: PatientProfile
}

struct PatientProfile: Codable, Identifiable {
    let id: String
    let patientCode: String
    let fullName: String
    let dateOfBirth: String?
    let gender: Gender?
    let phoneNumber: String?
    let caregiverName: String?
    let caregiverPhoneNumber: String?
    let diagnoses: [String]?
    let latestRiskLevel: RiskLevel?
    let latestCheckinAt: Date?
    let nextAppointmentAt: Date?
    let notes: String?
    let age: Int?
    let isActive: Bool?
}

struct PatientSummary: Codable, Identifiable {
    var id: String { patientId }
    let patientId: String
    let patientCode: String
    let fullName: String
    let age: Int?
    let diagnoses: [String]?
    let latestRiskLevel: RiskLevel?
    let latestSummary: String?
    let latestCheckinAt: Date?
    let handlingStatus: HandlingStatus?
    let unreadAlertCount: Int?
    let alertReasons: [String]?
    let caregiverAlertSentAt: Date?
    let missedMedicationDoses: Int?
    let patientPhone: String?
    let caregiverPhone: String?
}

struct Medication: Codable, Identifiable {
    let id: String?
    var name: String
    var strength: String?
    var dosage: String?
    var frequency: String?
    var timesOfDay: [MedicationTimeOfDay]?
    var instructions: String?
    var startDate: String?
    var endDate: String?
    var isActive: Bool?
}

struct MedicationListResponse: Decodable {
    let medications: [Medication]
}

struct FollowUpDraft: Codable {
    var appointmentAt: Date?
    var department: String?
    var doctorName: String?
}

struct Appointment: Codable, Identifiable {
    let id: String
    let appointmentAt: Date
    let department: String?
    let doctorName: String?
    let status: String?
}

struct AppointmentListResponse: Decodable {
    let appointments: [Appointment]
}

struct MedicalDocument: Codable, Identifiable {
    let id: String
    let documentType: DocumentType
    let status: String
    let confirmedAt: Date?
}
