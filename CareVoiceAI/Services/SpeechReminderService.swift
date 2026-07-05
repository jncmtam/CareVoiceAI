import AVFoundation
import Combine
import Foundation

@MainActor
final class SpeechReminderService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechReminderService()

    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var onFinished: (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        onFinished = nil
    }

    func speak(_ text: String, onFinished: (() -> Void)? = nil) {
        guard !text.cvTrimmed.isEmpty else { return }
        stop()
        self.onFinished = onFinished
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        synthesizer.speak(utterance)
    }

    func speakCheckinQuestion(_ text: String, onFinished: (() -> Void)? = nil) {
        speak(text, onFinished: onFinished)
    }

    func medicationPrompt(name: String, dosage: String?) -> String {
        let dose = dosage?.cvTrimmed ?? ""
        if dose.isEmpty {
            return String(format: L10n.text("adherence.voice_prompt"), name)
        }
        return String(format: L10n.text("adherence.voice_prompt_dose"), name, dose)
    }

    func speakCheckinResult(summary: String?, needsStaffReview: Bool) {
        if needsStaffReview {
            speak(L10n.text("patient.checkin.voice_attention"))
            return
        }
        speak(summary ?? L10n.text("patient.checkin.voice_ok"))
    }

    func speakMorningWelcome() {
        speak(L10n.text("patient.morning.voice_welcome"))
    }

    func speakDailyTip(_ text: String) {
        speak(text)
    }

    func speakStaffCriticalAlert(patientName: String) {
        speak(String(format: L10n.text("staff.critical.voice_alert"), patientName))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.onFinished?()
            self.onFinished = nil
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.onFinished = nil
        }
    }
}