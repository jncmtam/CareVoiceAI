import SwiftUI

struct TimelineEntryRow: View {
    let entry: TimelineEntry
    var patientPhone: String?
    var caregiverPhone: String?
    var onViewed: (() -> Void)?
    var onCalledBack: (() -> Void)?
    var onResolved: (() -> Void)?
    var onNote: (() -> Void)?

    @StateObject private var audioPlayer = AudioPlaybackService()
    @State private var isLoadingAudio = false
    @State private var audioError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            HStack(alignment: .top) {
                StickerIcon(systemImage: entryIcon, size: 40, iconSize: 18, tint: entryTint)
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(DateFormatters.shortDateTime.string(from: entry.occurredAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                Spacer()
                RiskBadge(level: entry.riskLevel)
            }

            if let statusLabel = patientStatusLabel {
                Label(statusLabel, systemImage: "person.fill.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.careVoicePrimary)
            }

            if entry.status == .analyzing || entry.status == .processing || entry.status == .transcribing {
                PollingStatusView(
                    title: entry.displayMessage ?? L10n.analyzingResponse,
                    systemImage: "waveform.and.mic"
                )
            } else {
                if let summary = entry.summary {
                    Text(summary)
                        .font(.body)
                        .foregroundColor(.primary)
                }
                if let transcript = entry.transcript {
                    Text(transcript)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
                if let reasons = entry.riskReasons, !reasons.isEmpty {
                    VStack(alignment: .leading, spacing: CVSpacing.xs) {
                        ForEach(reasons, id: \.self) { reason in
                            Label(reason, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if let hints = entry.analysisHints, !hints.isEmpty {
                    VStack(alignment: .leading, spacing: CVSpacing.xs) {
                        Text(L10n.text("staff.timeline.analysis_hints"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.careVoicePrimary)
                        ForEach(hints, id: \.self) { hint in
                            Label(hint, systemImage: "waveform.badge.magnifyingglass")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                if let staffNote = entry.staffNote, !staffNote.isEmpty {
                    VStack(alignment: .leading, spacing: CVSpacing.xs) {
                        Label(L10n.text("staff.timeline.note_label"), systemImage: "note.text")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.careVoicePrimary)
                        Text(staffNote)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        if let handledBy = entry.handledByName {
                            Text(String(format: L10n.text("staff.timeline.note_by"), handledBy))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(CVSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.careVoicePrimary.opacity(0.06))
                    .cornerRadius(CVCornerRadius.sm)
                }
            }

            if entry.audioUrl != nil, entry.status == .completed {
                SecondaryButton(
                    title: audioPlayer.isPlaying
                        ? L10n.text("staff.timeline.stop_audio")
                        : L10n.text("staff.timeline.play_audio"),
                    systemImage: audioPlayer.isPlaying ? "stop.circle.fill" : "speaker.wave.2.fill",
                    isDisabled: isLoadingAudio
                ) {
                    Task { await toggleTimelineAudio() }
                }
                if let audioError {
                    Text(audioError)
                        .font(.caption)
                        .foregroundColor(.riskIntervention)
                }
            }

            if entry.status == .completed {
                HStack(spacing: CVSpacing.sm) {
                    Button(action: { onViewed?() }) {
                        Label(L10n.markViewed, systemImage: "checkmark.circle")
                    }
                    if entry.handlingStatus != .calledBack, entry.handlingStatus != .resolved, onCalledBack != nil {
                        Button(action: { onCalledBack?() }) {
                            Label(L10n.text("staff.timeline.called_back"), systemImage: "phone.arrow.up.right")
                        }
                    }
                    if patientPhone != nil || caregiverPhone != nil {
                        Menu {
                            if let patientPhone {
                                Button {
                                    PhoneDialer.call(patientPhone)
                                } label: {
                                    Label(L10n.text("staff.call_patient"), systemImage: "phone.fill")
                                }
                            }
                            if let caregiverPhone {
                                Button {
                                    PhoneDialer.call(caregiverPhone)
                                } label: {
                                    Label(L10n.text("staff.call_caregiver"), systemImage: "phone.badge.waveform.fill")
                                }
                            }
                        } label: {
                            Label(L10n.text("staff.timeline.call_menu"), systemImage: "phone.fill")
                        }
                    }
                    Button(action: { onNote?() }) {
                        Label(L10n.addNote, systemImage: "square.and.pencil")
                    }
                    if entry.handlingStatus != .resolved, onResolved != nil {
                        Button(action: { onResolved?() }) {
                            Label(L10n.text("staff.timeline.mark_resolved"), systemImage: "checkmark.seal.fill")
                        }
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.careVoicePrimary)
            }
        }
        .cvGlossyCard()
        .accessibilityElement(children: .combine)
        .onDisappear {
            audioPlayer.stop()
        }
    }

    private var patientStatusLabel: String? {
        if let quickAnswerId = entry.quickAnswerId {
            switch quickAnswerId {
            case "normal":
                return L10n.text("patient.checkin.status_well")
            case "no":
                return L10n.text("patient.checkin.status_normal")
            case "yes":
                return L10n.text("patient.checkin.status_issue")
            default:
                break
            }
        }
        guard let declared = entry.patientDeclaredRiskLevel else { return nil }
        switch declared {
        case .normal:
            return L10n.text("patient.checkin.status_well")
        case .attention:
            return L10n.text("patient.checkin.status_issue")
        case .intervention:
            return L10n.text("staff.risk.intervention_short")
        }
    }

    @MainActor
    private func toggleTimelineAudio() async {
        if audioPlayer.isPlaying {
            audioPlayer.stop()
            return
        }
        guard let audioURL = entry.audioUrl else { return }
        isLoadingAudio = true
        audioError = nil
        defer { isLoadingAudio = false }
        do {
            let file = try await AudioCache.shared.cachedFile(for: audioURL, cacheKey: entry.id)
            try audioPlayer.play(fileURL: file)
        } catch {
            audioError = L10n.text("staff.timeline.audio_error")
        }
    }

    private var title: String {
        switch entry.type {
        case .checkinResponse:
            return L10n.text("timeline.checkin")
        case .hotlineQuestion:
            return L10n.text("timeline.hotline")
        case .medicationUpdate:
            return L10n.text("timeline.medication")
        case .appointment:
            return L10n.text("timeline.appointment")
        }
    }

    private var entryIcon: String {
        switch entry.type {
        case .checkinResponse:
            return "heart.text.square.fill"
        case .hotlineQuestion:
            return "questionmark.bubble.fill"
        case .medicationUpdate:
            return "pills.fill"
        case .appointment:
            return "calendar.badge.clock"
        }
    }

    private var entryTint: Color {
        switch entry.riskLevel {
        case .some(.intervention):
            return .riskIntervention
        case .some(.attention):
            return .riskAttention
        default:
            return .careVoicePrimary
        }
    }
}