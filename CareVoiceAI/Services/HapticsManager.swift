import AudioToolbox
import UIKit

enum HapticsManager {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func urgent() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func critical() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1.0)
        }
    }

    /// Two-tone alert pattern for staff dashboard (distinct from default notification sound).
    static func playStaffCriticalAlertSound() {
        AudioServicesPlaySystemSound(1013)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            AudioServicesPlaySystemSound(1304)
        }
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
