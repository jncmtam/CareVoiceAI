import Foundation

@MainActor
final class PatientNavigationCoordinator: ObservableObject {
    static let shared = PatientNavigationCoordinator()

    @Published var selectedTab = 0
    @Published var pendingMedicationId: String?
    @Published var pendingMedicationSlot: String?

    private init() {}

    func openMedicationAdherence(medicationId: String, slot: String) {
        pendingMedicationId = medicationId
        pendingMedicationSlot = slot
        selectedTab = 2
    }

    func consumePendingMedicationTarget() -> (medicationId: String, slot: String)? {
        guard let medicationId = pendingMedicationId, let slot = pendingMedicationSlot else { return nil }
        pendingMedicationId = nil
        pendingMedicationSlot = nil
        return (medicationId, slot)
    }
}