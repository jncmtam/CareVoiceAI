import AVFoundation
import Foundation

@MainActor
final class AudioRecorderService: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var level: CGFloat = 0
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var lastDuration: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startedAt: Date?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() async throws {
        guard await requestPermission() else {
            throw APIError.file(message: L10n.text("error.microphone_denied"))
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let url = FileStorage.recordingsDirectory.appendingPathComponent(
            FileStorage.stableFileName(prefix: "answer", extension: "m4a")
        )
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        self.recorder = recorder
        self.startedAt = Date()
        self.lastRecordingURL = nil
        self.lastDuration = 0
        self.isRecording = true

        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMeter()
            }
        }
    }

    func stopRecording() {
        guard let recorder else { return }
        recorder.updateMeters()
        lastDuration = recorder.currentTime
        let url = recorder.url
        recorder.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        self.recorder = nil
        isRecording = false
        level = 0
        lastRecordingURL = url
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func waitUntilRecordingFileIsReady(at url: URL, timeout: TimeInterval = 1.5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var previousSize: UInt64?
        while Date() < deadline {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? UInt64,
                  size > 1024
            else {
                try? await Task.sleep(nanoseconds: 80_000_000)
                continue
            }
            if let previousSize, previousSize == size {
                return true
            }
            previousSize = size
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64).map { $0 > 0 } ?? false
    }

    func cancelRecording() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        isRecording = false
        lastRecordingURL = nil
        lastDuration = 0
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func clearRecording() {
        lastRecordingURL = nil
        lastDuration = 0
    }

    private func updateMeter() {
        recorder?.updateMeters()
        let power = recorder?.averagePower(forChannel: 0) ?? -80
        let normalized = max(0, min(1, CGFloat((power + 55) / 55)))
        level = normalized
    }
}
