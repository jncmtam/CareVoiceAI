import SwiftUI

struct TodayCheckinView: View {
    @StateObject private var viewModel = TodayCheckinViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: CVSpacing.xl) {
                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage) {
                        Task { await viewModel.load() }
                    }
                }

                if let offline = viewModel.offlineMessage {
                    PollingStatusView(title: offline, progress: nil)
                }

                content
            }
            .padding(CVSpacing.lg)
        }
        .cvDismissKeyboardOnScroll()
        .background(Color.appBackground)
        .navigationTitle(L10n.todayCheckin)
        .navigationBarTitleDisplayMode(.inline)
        .cvKeyboardDoneToolbar()
        .task {
            await viewModel.load()
            await viewModel.autoPlayQuestionIfNeeded()
        }
        .onDisappear {
            viewModel.stopQuestionPlayback()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingView(title: L10n.preparingQuestion)
        case .failed(let error):
            ErrorBannerView(message: error.userMessage) {
                Task { await viewModel.load() }
            }
        case .empty(let message):
            EmptyStateView(title: message)
        case .loaded(let checkin):
            if viewModel.analysisResult != nil {
                completedFlow
            } else {
                activeFlow(checkin: checkin)
            }
        }
    }

    private var completedFlow: some View {
        VStack(spacing: CVSpacing.lg) {
            StickerLabel(
                text: L10n.text("patient.checkin.completed_badge"),
                systemImage: "checkmark.seal.fill",
                font: .subheadline.weight(.semibold),
                tint: .riskNormal
            )
            if let checkin = viewModel.checkin {
                SpeakingAvatarView(
                    isActive: false,
                    subtitle: checkin.questionText,
                    replayHint: L10n.text("patient.checkin.ai_replay_hint")
                ) {
                    Task { await viewModel.playQuestion() }
                }
                .cvGlossyCard(elevation: .raised, tint: .careVoicePrimary)
            }
            if let result = viewModel.analysisResult {
                completedResultCard(result)
            } else {
                Text(L10n.text("patient.checkin.sent"))
                    .font(CVFont.patientBody)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cvGlossyCard(elevation: .raised)
            }
        }
    }

    private func activeFlow(checkin: Checkin) -> some View {
        VStack(spacing: CVSpacing.xl) {
            CheckinFlowStepBar(
                activeStep: activeCheckinStep,
                isListening: viewModel.isAISpeaking
            )

            SpeakingAvatarView(
                isActive: viewModel.isAISpeaking,
                subtitle: checkin.questionText,
                replayHint: L10n.text("patient.checkin.ai_replay_hint")
            ) {
                Task { await viewModel.playQuestion() }
            }
            .cvGlossyCard(elevation: .hero, tint: .careVoicePrimary)

            if checkin.audioStatus == .generating {
                PollingStatusView(title: L10n.preparingQuestion, progress: nil)
            }

            if viewModel.isAISpeaking {
                VStack(spacing: CVSpacing.sm) {
                    PollingStatusView(
                        title: L10n.text("patient.checkin.listen_prompt"),
                        progress: nil
                    )
                    SecondaryButton(
                        title: L10n.text("patient.checkin.skip_listen"),
                        systemImage: "forward.fill"
                    ) {
                        viewModel.skipQuestionPlayback()
                    }
                }
            }

            responseSection(checkin: checkin)

            if viewModel.isTranscribing || viewModel.isSubmitting {
                PollingStatusView(
                    title: viewModel.isTranscribing
                        ? L10n.text("patient.checkin.transcribing")
                        : (viewModel.pollingMessage ?? L10n.analyzingResponse),
                    progress: nil
                )
            }

            if let message = viewModel.pollingMessage, !viewModel.isSubmitting {
                PollingStatusView(title: message, progress: nil)
            }

            if let notifiedAt = viewModel.caregiverNotifiedAt {
                CaregiverNotifiedBanner(
                    caregiverName: viewModel.caregiverName,
                    sentAt: notifiedAt
                )
            }
        }
    }

    private var activeCheckinStep: CheckinFlowStepBar.Step {
        if viewModel.isAISpeaking {
            return .listen
        }
        if viewModel.selectedQuickAnswerId != nil {
            return .confirm
        }
        if viewModel.recorder.isRecording || viewModel.isTranscribing {
            return .speak
        }
        return .speak
    }

    private func responseSection(checkin: Checkin) -> some View {
        VStack(spacing: CVSpacing.lg) {
            statusSection(checkin.quickAnswers)

            VStack(spacing: CVSpacing.lg) {
                SectionHeaderView(
                    title: L10n.text("patient.checkin.voice_optional_title"),
                    systemImage: "mic.circle.fill",
                    subtitle: L10n.text("patient.checkin.voice_optional_hint")
                )

                RecordingButton(
                    isRecording: viewModel.recorder.isRecording,
                    level: viewModel.recorder.level
                ) {
                    Task { await viewModel.toggleRecording() }
                }
                .frame(maxWidth: .infinity)
                .pulseBorder(active: viewModel.recorder.isRecording, color: .riskIntervention)

                if viewModel.recorder.lastRecordingURL != nil {
                    SecondaryButton(
                        title: L10n.playRecording,
                        systemImage: "play.circle.fill"
                    ) {
                        viewModel.playRecording()
                    }
                }
            }
            .cvGlossyCard(elevation: .raised)

            if !viewModel.draftTranscript.cvTrimmed.isEmpty {
                transcriptEditor
            }

            PrimaryButton(
                title: L10n.text("patient.checkin.confirm_send"),
                systemImage: "paperplane.fill",
                isLoading: viewModel.isSubmitting,
                isDisabled: !viewModel.canSubmitCheckin || viewModel.isSubmitting
            ) {
                Task { await viewModel.confirmAndSubmit() }
            }
        }
    }

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: CVSpacing.sm) {
            SectionHeaderView(
                title: L10n.text("patient.checkin.review_title"),
                systemImage: "text.badge.checkmark",
                subtitle: L10n.text("patient.checkin.review_hint_short")
            )
            ZStack(alignment: .topLeading) {
                if viewModel.draftTranscript.cvTrimmed.isEmpty {
                    Text(L10n.text("patient.checkin.symptoms_placeholder"))
                        .font(CVFont.patientBody)
                        .foregroundColor(.secondary.opacity(0.85))
                        .padding(.horizontal, CVSpacing.md)
                        .padding(.vertical, CVSpacing.md)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $viewModel.draftTranscript)
                    .font(CVFont.patientBody)
                    .padding(CVSpacing.xs)
            }
            .frame(minHeight: 100)
            .background(Color.appSurface)
            .cornerRadius(CVCornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CVCornerRadius.sm)
                    .stroke(Color.careVoicePrimary.opacity(0.18), lineWidth: 1)
            )
        }
        .cvGlossyCard(elevation: .raised, tint: .careVoicePrimary)
    }

    private func statusSection(_ answers: [QuickAnswer]) -> some View {
        VStack(alignment: .leading, spacing: CVSpacing.sm) {
            SectionHeaderView(
                title: L10n.text("patient.checkin.status_title"),
                systemImage: "heart.text.square.fill",
                subtitle: L10n.text("patient.checkin.status_hint")
            )
            HStack(spacing: CVSpacing.sm) {
                ForEach(orderedStatusAnswers(answers)) { answer in
                    Button(action: {
                        viewModel.applyQuickAnswer(answer)
                    }) {
                        Text(viewModel.friendlyStatusLabel(for: answer.id, fallback: answer.label))
                            .font(CVFont.patientAction)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .foregroundColor(viewModel.selectedQuickAnswerId == answer.id ? .white : .careVoicePrimary)
                            .background(
                                viewModel.selectedQuickAnswerId == answer.id
                                    ? statusTint(for: answer.id)
                                    : statusTint(for: answer.id).opacity(0.12)
                            )
                            .cornerRadius(CVCornerRadius.sm)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(viewModel.isSubmitting)
                }
            }
        }
        .cvGlossyCard(elevation: .raised)
    }

    private func orderedStatusAnswers(_ answers: [QuickAnswer]) -> [QuickAnswer] {
        let order = ["normal", "no", "yes"]
        return order.compactMap { id in answers.first(where: { $0.id == id }) }
            + answers.filter { !order.contains($0.id) }
    }

    private func statusTint(for answerId: String) -> Color {
        switch answerId {
        case "yes":
            return .riskAttention
        case "normal", "no":
            return .riskNormal
        default:
            return .careVoicePrimary
        }
    }

    private func completedResultCard(_ result: CheckinJobResponse) -> some View {
        VStack(alignment: .leading, spacing: CVSpacing.sm) {
            Text(result.displayMessage ?? L10n.text("patient.checkin.completed_badge"))
                .font(.headline)
                .foregroundColor(.primary)
            RiskBadge(level: result.risk?.level)
            if let transcript = result.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(CVFont.patientBody)
                    .foregroundColor(.primary)
            }
            Text(result.summary ?? L10n.text("patient.checkin.sent"))
                .font(CVFont.patientBody)
                .foregroundColor(.primary)
            if let reasons = result.risk?.reasons, !reasons.isEmpty {
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(L10n.text("patient.checkin.reasons_title"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(reasons, id: \.self) { reason in
                        Label(reason, systemImage: "info.circle.fill")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if let hints = result.risk?.analysisHints, !hints.isEmpty {
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(L10n.text("patient.checkin.analysis_hints_title"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(hints, id: \.self) { hint in
                        Label(hint, systemImage: "waveform.badge.magnifyingglass")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if result.risk?.needsStaffReview == true {
                Text(L10n.text("patient.checkin.human_review_note"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if !viewModel.isAISpeaking {
                SecondaryButton(
                    title: L10n.text("patient.checkin.listen_result"),
                    systemImage: "speaker.wave.2.fill"
                ) {
                    SpeechReminderService.shared.speakCheckinResult(
                        summary: result.summary,
                        needsStaffReview: result.risk?.needsStaffReview == true
                    )
                }
            }
        }
        .cvGlossyCard(elevation: .raised)
    }
}