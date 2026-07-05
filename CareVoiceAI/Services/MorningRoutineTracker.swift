import Foundation
import SwiftUI

@MainActor
final class MorningRoutineTracker: ObservableObject {
    static let shared = MorningRoutineTracker()

    static let totalSteps = 3

    @AppStorage("morning_checkin_day") private var checkinDay = ""
    @AppStorage("morning_medication_day") private var medicationDay = ""
    @AppStorage("morning_face_day") private var faceDay = ""

    private init() {}

    var checkinCompleted: Bool { checkinDay == todayKey }
    var medicationCompleted: Bool { medicationDay == todayKey }
    var faceVerifyCompleted: Bool { faceDay == todayKey }

    var completedSteps: Int {
        [checkinCompleted, medicationCompleted, faceVerifyCompleted].filter { $0 }.count
    }

    var progressFraction: Double {
        Double(completedSteps) / Double(Self.totalSteps)
    }

    var isMorningComplete: Bool { completedSteps == Self.totalSteps }

    func markCheckinDone() {
        checkinDay = todayKey
        objectWillChange.send()
    }

    func markMedicationDone() {
        medicationDay = todayKey
        objectWillChange.send()
    }

    func markFaceVerifyDone() {
        faceDay = todayKey
        objectWillChange.send()
    }

    func resetIfNewDay() {
        guard checkinDay != todayKey || medicationDay != todayKey || faceDay != todayKey else { return }
        if checkinDay != todayKey { checkinDay = "" }
        if medicationDay != todayKey { medicationDay = "" }
        if faceDay != todayKey { faceDay = "" }
        objectWillChange.send()
    }

    private var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}