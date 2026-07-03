import SwiftUI

struct RecordingButton: View {
    let isRecording: Bool
    let level: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button(action: {
            HapticsManager.tap()
            action()
        }) {
            ZStack {
                if isRecording {
                    Circle()
                        .stroke(Color.riskIntervention.opacity(0.24), lineWidth: 10)
                        .scaleEffect(reduceMotion ? 1 : (pulse ? 1.16 : 1.0))
                        .opacity(reduceMotion ? 1 : (pulse ? 0.2 : 0.8))
                }
                Circle()
                    .fill(isRecording ? Color.riskIntervention : Color.careVoicePrimary)
                    .frame(width: 116, height: 116)
                    .overlay(
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.white)
                    )
                if isRecording {
                    WaveformView(level: level)
                        .frame(width: 78, height: 24)
                        .offset(y: 72)
                }
            }
            .frame(width: 156, height: 176)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(isRecording ? L10n.stopRecording : L10n.recordAnswer)
        .onAppear {
            pulse = true
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
    }
}

private struct WaveformView: View {
    let level: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(Color.riskIntervention)
                    .frame(width: 8, height: max(8, 10 + level * CGFloat(10 + index * 4)))
            }
        }
        .accessibilityHidden(true)
    }
}
