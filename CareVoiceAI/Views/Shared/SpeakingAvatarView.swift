import SwiftUI

struct SpeakingAvatarView: View {
    let isActive: Bool
    var subtitle: String?
    var statusText: String? = nil
    var replayHint: String? = nil
    let onTap: () -> Void

    @State private var wavePhase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: CVSpacing.md) {
                ZStack {
                    if isActive && !reduceMotion {
                        ForEach(0..<3, id: \.self) { ring in
                            Circle()
                                .stroke(Color.careVoicePrimary.opacity(0.22 - Double(ring) * 0.05), lineWidth: 3)
                                .frame(width: 108 + CGFloat(ring) * 28, height: 108 + CGFloat(ring) * 28)
                                .scaleEffect(wavePhase ? 1.08 : 0.94)
                                .opacity(wavePhase ? 0.15 : 0.55)
                        }
                    }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.careVoicePrimary.opacity(isActive ? 0.95 : 0.82),
                                    Color.careVoicePrimaryGradientBottom
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 108, height: 108)
                        .overlay {
                            if isActive {
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(.system(size: 42, weight: .semibold))
                                    .foregroundColor(.white)
                                    .scaleEffect(wavePhase && !reduceMotion ? 1.06 : 1)
                            } else {
                                CareVoiceLogo(variant: .patient, size: 72, showPulse: false)
                            }
                        }
                        .shadow(color: Color.careVoicePrimary.opacity(0.28), radius: 14, x: 0, y: 8)

                    SpeakingWaveBars(isActive: isActive, phase: wavePhase)
                        .offset(y: 62)
                }
                .frame(height: 188)

                Text(
                    statusText
                        ?? (isActive
                            ? L10n.text("patient.checkin.ai_speaking")
                            : (replayHint ?? L10n.text("patient.checkin.ai_ready")))
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isActive ? .careVoicePrimary : .secondary)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(CVSpacing.lg)
            .background(Color.careVoicePrimary.opacity(0.08))
            .cornerRadius(CVCornerRadius.md)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            guard isActive, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                wavePhase = true
            }
        }
        .onChange(of: isActive) { active in
            if active && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    wavePhase = true
                }
            } else {
                wavePhase = false
            }
        }
    }
}

private struct SpeakingWaveBars: View {
    let isActive: Bool
    let phase: Bool

    private let heights: [CGFloat] = [14, 24, 32, 22, 16]

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, base in
                Capsule()
                    .fill(Color.careVoicePrimary.opacity(0.85))
                    .frame(
                        width: 7,
                        height: isActive ? base * (phase ? 1.15 : 0.75) : 8
                    )
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(index) * 0.08)
                            : nil,
                        value: phase
                    )
            }
        }
        .frame(height: 36)
        .accessibilityHidden(true)
    }
}

struct CheckinIntentPicker: View {
    @Binding var selectedIntent: RiskLevel?
    var suggestedIntent: RiskLevel?

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.sm) {
            HStack {
                Text(L10n.text("patient.checkin.intent_title"))
                    .font(.headline)
                if let suggestedIntent {
                    Text(String(format: L10n.text("patient.checkin.intent_suggested"), L10n.text("risk.\(suggestedIntent.rawValue)")))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: CVSpacing.sm) {
                intentButton(.normal, title: L10n.text("risk.normal"), icon: "checkmark.circle.fill", tint: .riskNormal)
                intentButton(.attention, title: L10n.text("risk.attention"), icon: "exclamationmark.circle.fill", tint: .riskAttention)
                intentButton(.intervention, title: L10n.text("risk.intervention"), icon: "bolt.heart.fill", tint: .riskIntervention)
            }
        }
    }

    private func intentButton(_ level: RiskLevel, title: String, icon: String, tint: Color) -> some View {
        Button {
            selectedIntent = level
            HapticsManager.selection()
        } label: {
            HStack(spacing: CVSpacing.md) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(CVFont.patientAction)
                Spacer()
                if selectedIntent == level {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                }
            }
            .foregroundColor(selectedIntent == level ? .white : tint)
            .padding(.horizontal, CVSpacing.lg)
            .frame(minHeight: 58)
            .background(selectedIntent == level ? tint : tint.opacity(0.12))
            .cornerRadius(CVCornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CVCornerRadius.sm)
                    .stroke(tint.opacity(selectedIntent == level ? 0 : 0.35), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CheckinVoiceReviewCard: View {
    @Binding var transcript: String
    @Binding var selectedIntent: RiskLevel?
    var suggestedIntent: RiskLevel?

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.lg) {
            SectionHeaderView(
                title: L10n.text("patient.checkin.review_title"),
                systemImage: "text.badge.checkmark",
                subtitle: L10n.text("patient.checkin.review_hint")
            )

            ZStack(alignment: .topLeading) {
                if transcript.cvTrimmed.isEmpty {
                    Text(L10n.text("patient.checkin.symptoms_placeholder"))
                        .font(CVFont.patientBody)
                        .foregroundColor(.secondary.opacity(0.85))
                        .padding(.horizontal, CVSpacing.md)
                        .padding(.vertical, CVSpacing.md)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $transcript)
                    .font(CVFont.patientBody)
                    .padding(CVSpacing.xs)
            }
            .frame(minHeight: 120)
            .background(Color.appSurface)
            .cornerRadius(CVCornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CVCornerRadius.sm)
                    .stroke(Color.careVoicePrimary.opacity(0.18), lineWidth: 1)
            )

            CheckinIntentPicker(selectedIntent: $selectedIntent, suggestedIntent: suggestedIntent)
        }
        .cvGlossyCard(elevation: .raised, tint: .careVoicePrimary)
    }
}