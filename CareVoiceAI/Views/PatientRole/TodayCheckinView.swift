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
        .background(Color.appBackground)
        .navigationTitle(L10n.todayCheckin)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
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
            VStack(spacing: CVSpacing.xl) {
                Text(checkin.questionText)
                    .font(CVFont.patientTitle)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)

                if checkin.audioStatus == .generating {
                    PollingStatusView(title: L10n.preparingQuestion, progress: nil)
                } else if checkin.audioStatus == .ready, checkin.audioUrl != nil {
                    SecondaryButton(title: L10n.listenQuestion, systemImage: "speaker.wave.2.fill") {
                        Task { await viewModel.playQuestion() }
                    }
                } else {
                    Label(L10n.text("patient.checkin.text_only"), systemImage: "text.bubble.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(CVSpacing.md)
                        .background(Color.careVoicePrimary.opacity(0.08))
                        .cornerRadius(8)
                }

                quickAnswers(checkin.quickAnswers)

                RecordingButton(
                    isRecording: viewModel.recorder.isRecording,
                    level: viewModel.recorder.level
                ) {
                    Task { await viewModel.toggleRecording() }
                }

                if viewModel.recorder.lastRecordingURL != nil {
                    SecondaryButton(title: L10n.playRecording, systemImage: "play.circle.fill") {
                        viewModel.playRecording()
                    }
                }

                if let message = viewModel.pollingMessage {
                    PollingStatusView(title: message, progress: nil)
                }

                if let result = viewModel.analysisResult {
                    VStack(alignment: .leading, spacing: CVSpacing.sm) {
                        RiskBadge(level: result.risk?.level)
                        Text(result.summary ?? L10n.text("patient.checkin.sent"))
                            .font(CVFont.patientBody)
                            .foregroundColor(.primary)
                        Text(L10n.text("patient.checkin.human_review_note"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .cvCard()
                }

                PrimaryButton(
                    title: L10n.sendAnswer,
                    systemImage: "paperplane.fill",
                    isLoading: viewModel.isSubmitting,
                    isDisabled: viewModel.recorder.lastRecordingURL == nil && viewModel.selectedQuickAnswerId == nil
                ) {
                    Task { await viewModel.submit() }
                }
            }
        }
    }

    private func quickAnswers(_ answers: [QuickAnswer]) -> some View {
        HStack(spacing: CVSpacing.sm) {
            ForEach(answers.prefix(3)) { answer in
                Button(action: {
                    viewModel.selectedQuickAnswerId = answer.id
                    HapticsManager.tap()
                }) {
                    Text(answer.label)
                        .font(CVFont.patientAction)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundColor(viewModel.selectedQuickAnswerId == answer.id ? .white : .careVoicePrimary)
                        .background(viewModel.selectedQuickAnswerId == answer.id ? Color.careVoicePrimary : Color.careVoicePrimary.opacity(0.10))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}
