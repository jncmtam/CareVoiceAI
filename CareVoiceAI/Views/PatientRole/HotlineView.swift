import SwiftUI

struct HotlineView: View {
    @StateObject private var viewModel = HotlineViewModel()
    @State private var appeared = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CVSpacing.lg) {
                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage)
                        .cvStaggeredAppear(index: 0, isVisible: appeared)
                }

                if let offlineMessage = viewModel.offlineMessage {
                    HStack(spacing: CVSpacing.md) {
                        StickerIcon(systemImage: "icloud.and.arrow.up", size: 40, iconSize: 18, tint: .riskAttention)
                        Text(offlineMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .cvGlossyCard(tint: .riskAttention)
                    .cvStaggeredAppear(index: 1, isVisible: appeared)
                }

                if viewModel.isProcessing, let message = viewModel.processingMessage {
                    PollingStatusView(title: message, systemImage: processingIcon)
                        .cvStaggeredAppear(index: 2, isVisible: appeared)
                }

                textQuestionSection
                    .cvStaggeredAppear(index: 3, isVisible: appeared)

                voiceQuestionSection
                    .cvStaggeredAppear(index: 4, isVisible: appeared)

                if viewModel.latestAnswer != nil || viewModel.latestTranscript != nil {
                    resultSection
                        .cvStaggeredAppear(index: 5, isVisible: appeared)
                }

                if !viewModel.history.isEmpty {
                    historySection
                        .cvStaggeredAppear(index: 6, isVisible: appeared)
                }
            }
            .padding(CVSpacing.lg)
        }
        .cvDismissKeyboardOnScroll()
        .background(Color.appBackground)
        .navigationTitle(L10n.hotline)
        .cvKeyboardDoneToolbar()
        .task { await viewModel.loadHistory() }
        .refreshable { await viewModel.loadHistory() }
        .onAppear { appeared = true }
    }

    private var processingIcon: String {
        switch viewModel.processingStatus {
        case .transcribing:
            return "waveform.and.mic"
        case .processing, .analyzing, .summarizing:
            return "brain.head.profile"
        default:
            return "ellipsis.circle"
        }
    }

    private var textQuestionSection: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.askQuestion,
                systemImage: "text.bubble.fill",
                subtitle: L10n.text("hotline.text_hint")
            )
            TextEditor(text: $viewModel.questionText)
                .frame(minHeight: 110)
                .padding(CVSpacing.sm)
                .background(Color.appSurface)
                .cornerRadius(CVCornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CVCornerRadius.sm)
                        .stroke(Color.careVoicePrimary.opacity(0.14), lineWidth: 1)
                )
            PrimaryButton(
                title: L10n.send,
                systemImage: "paperplane.fill",
                isLoading: viewModel.isLoading && !viewModel.isProcessing,
                isDisabled: viewModel.questionText.cvTrimmed.isEmpty || viewModel.isProcessing
            ) {
                Task { await viewModel.sendText() }
            }
        }
        .cvGlossyCard(elevation: .raised)
    }

    private var voiceQuestionSection: some View {
        VStack(spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.tapToTalk,
                systemImage: "mic.circle.fill",
                subtitle: viewModel.recorder.isRecording
                    ? L10n.text("hotline.recording_active")
                    : L10n.text("hotline.voice_two_step_hint")
            )
            RecordingButton(isRecording: viewModel.recorder.isRecording, level: viewModel.recorder.level) {
                Task { await viewModel.toggleRecording() }
            }
            if viewModel.hasPendingVoice {
                SecondaryButton(title: L10n.playRecording, systemImage: "play.circle.fill") {
                    viewModel.playPendingVoice()
                }
                PrimaryButton(
                    title: L10n.text("hotline.confirm_send_voice"),
                    systemImage: "paperplane.fill",
                    isLoading: viewModel.isLoading || viewModel.isProcessing,
                    isDisabled: viewModel.isLoading || viewModel.isProcessing
                ) {
                    Task { await viewModel.confirmSendVoice() }
                }
            }
            Text(L10n.text("hotline.voice_symptom_hint"))
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .cvGlossyCard(elevation: .hero, tint: .careVoicePrimary)
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.text("hotline.result_title"),
                systemImage: "brain.head.profile",
                tint: resultTint
            )

            if let riskLevel = viewModel.latestRiskLevel {
                RiskBadge(level: riskLevel)
            }

            if let transcript = viewModel.latestTranscript, !transcript.isEmpty {
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(L10n.text("hotline.transcript_title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(transcript)
                        .font(CVFont.patientBody)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let answer = viewModel.latestAnswer, !answer.isEmpty {
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(L10n.text("hotline.answer_title"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(answer)
                        .font(CVFont.patientBody)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !viewModel.latestReasons.isEmpty {
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(L10n.text("hotline.reasons_title"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(viewModel.latestReasons, id: \.self) { reason in
                        Label(reason, systemImage: "info.circle.fill")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if viewModel.needsStaffReview {
                HStack(spacing: CVSpacing.sm) {
                    StickerIcon(systemImage: "person.crop.circle.badge.exclamationmark", size: 32, iconSize: 14, tint: .riskAttention)
                    Text(L10n.text("hotline.needs_review"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.riskAttention)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(CVSpacing.sm)
                .background(Color.riskAttention.opacity(0.1))
                .cornerRadius(CVCornerRadius.sm)
            }
        }
        .cvGlossyCard(elevation: .raised, tint: resultTint)
    }

    private var resultTint: Color {
        switch viewModel.latestRiskLevel {
        case .intervention:
            return .riskIntervention
        case .attention:
            return .riskAttention
        case .normal:
            return .riskNormal
        case .none:
            return .careVoicePrimary
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.text("hotline.history_title"),
                systemImage: "clock.arrow.circlepath"
            )
            ForEach(viewModel.history) { item in
                HotlineHistoryRow(item: item)
            }
        }
        .cvGlossyCard()
    }
}

private struct HotlineHistoryRow: View {
    let item: HotlineHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.sm) {
            HStack(spacing: CVSpacing.sm) {
                StickerIcon(systemImage: "questionmark.bubble.fill", size: 28, iconSize: 12)
                Text(DateFormatters.shortDateTime.string(from: item.askedAt))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if let riskLevel = item.riskLevel {
                    RiskBadge(level: riskLevel)
                } else if item.needsStaffReview == true {
                    StickerIcon(systemImage: "exclamationmark.circle.fill", size: 24, iconSize: 11, tint: .riskAttention)
                }
            }
            if let question = item.transcript ?? item.questionText {
                Text(question)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
            }
            if let reasons = item.reasons, !reasons.isEmpty {
                ForEach(reasons.prefix(2), id: \.self) { reason in
                    Label(reason, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if let answer = item.answerText {
                HStack(alignment: .top, spacing: CVSpacing.sm) {
                    StickerIcon(systemImage: "sparkles", size: 24, iconSize: 11, tint: .riskNormal)
                    Text(answer)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(CVSpacing.md)
        .background(Color.appBackground.opacity(0.55))
        .cornerRadius(CVCornerRadius.sm)
    }
}