import Foundation
import SwiftUI

@MainActor
final class MedicationAdherenceTracker: ObservableObject {
    static let shared = MedicationAdherenceTracker()

    @Published private(set) var recordedSlots: Set<String> = []
    @AppStorage("medication_adherence_day") private var storedDay = ""
    @AppStorage("medication_adherence_slots") private var storedSlots = ""

    private init() {
        resetIfNewDay()
    }

    func slotKey(medicationId: String, slot: String) -> String {
        "\(medicationId)-\(slot)"
    }

    func isRecorded(medicationId: String, slot: String) -> Bool {
        resetIfNewDay()
        return recordedSlots.contains(slotKey(medicationId: medicationId, slot: slot))
    }

    func markRecorded(medicationId: String, slot: String) {
        resetIfNewDay()
        recordedSlots.insert(slotKey(medicationId: medicationId, slot: slot))
        persist()
    }

    func resetIfNewDay() {
        let today = todayKey
        guard storedDay != today else {
            if recordedSlots.isEmpty, !storedSlots.isEmpty {
                recordedSlots = Set(storedSlots.split(separator: "|").map(String.init))
            }
            return
        }
        storedDay = today
        storedSlots = ""
        recordedSlots = []
    }

    private func persist() {
        storedDay = todayKey
        storedSlots = recordedSlots.sorted().joined(separator: "|")
    }

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}