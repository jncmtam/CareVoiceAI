import Foundation
import SwiftUI

@MainActor
final class MorningRoutineTracker: ObservableObject {
    static let shared = MorningRoutineTracker()

    static let totalSteps = 2

    @AppStorage("morning_medication_day") private var medicationDay = ""
    @AppStorage("morning_daily_tip_day") private var dailyTipDay = ""

    private init() {}

    var medicationCompleted: Bool { medicationDay == todayKey }
    var dailyTipCompleted: Bool { dailyTipDay == todayKey }

    var completedSteps: Int {
        [medicationCompleted, dailyTipCompleted].filter { $0 }.count
    }

    var progressFraction: Double {
        Double(completedSteps) / Double(Self.totalSteps)
    }

    var isMorningComplete: Bool { completedSteps == Self.totalSteps }

    func markMedicationDone() {
        medicationDay = todayKey
        objectWillChange.send()
    }

    func markDailyTipDone() {
        dailyTipDay = todayKey
        objectWillChange.send()
    }

    func resetIfNewDay() {
        guard medicationDay != todayKey || dailyTipDay != todayKey else { return }
        if medicationDay != todayKey { medicationDay = "" }
        if dailyTipDay != todayKey { dailyTipDay = "" }
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