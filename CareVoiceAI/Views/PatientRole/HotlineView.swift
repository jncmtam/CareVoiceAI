import SwiftUI

struct HotlineView: View {
    @StateObject private var viewModel = HotlineViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CVSpacing.lg) {
                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage)
                }

                VStack(alignment: .leading, spacing: CVSpacing.md) {
                    Text(L10n.askQuestion)
                        .font(CVFont.patientTitle)
                    TextEditor(text: $viewModel.questionText)
                        .frame(minHeight: 110)
                        .padding(CVSpacing.sm)
                        .background(Color.appSurface)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                    PrimaryButton(
                        title: L10n.send,
                        systemImage: "paperplane.fill",
                        isLoading: viewModel.isLoading,
                        isDisabled: viewModel.questionText.cvTrimmed.isEmpty
                    ) {
                        Task { await viewModel.sendText() }
                    }
                }
                .cvCard()

                VStack(spacing: CVSpacing.md) {
                    Text(L10n.tapToTalk)
                        .font(CVFont.patientBody)
                    RecordingButton(isRecording: viewModel.recorder.isRecording, level: viewModel.recorder.level) {
                        Task { await viewModel.toggleRecording() }
                    }
                    if viewModel.recorder.lastRecordingURL != nil {
                        PrimaryButton(
                            title: L10n.send,
                            systemImage: "mic.fill",
                            isLoading: viewModel.isLoading
                        ) {
                            Task { await viewModel.sendVoice() }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .cvCard()

                if let answer = viewModel.latestAnswer {
                    VStack(alignment: .leading, spacing: CVSpacing.sm) {
                        Text(answer)
                            .font(CVFont.patientBody)
                        if viewModel.needsStaffReview {
                            Label(L10n.text("hotline.needs_review"), systemImage: "person.crop.circle.badge.exclamationmark")
                                .foregroundColor(.riskAttention)
                        }
                    }
                    .cvCard()
                }

                ForEach(viewModel.history) { item in
                    VStack(alignment: .leading, spacing: CVSpacing.sm) {
                        Text(DateFormatters.shortDateTime.string(from: item.askedAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let question = item.questionText {
                            Text(question)
                                .font(.body.weight(.semibold))
                        }
                        if let answer = item.answerText {
                            Text(answer)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    .cvCard()
                }
            }
            .padding(CVSpacing.lg)
        }
        .background(Color.appBackground)
        .navigationTitle(L10n.hotline)
        .task { await viewModel.loadHistory() }
        .refreshable { await viewModel.loadHistory() }
    }
}
