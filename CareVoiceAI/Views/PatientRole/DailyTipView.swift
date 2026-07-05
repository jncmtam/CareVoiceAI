import SwiftUI

struct DailyTipView: View {
    @StateObject private var viewModel = DailyTipViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: CVSpacing.xl) {
                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage) {
                        Task { await viewModel.load() }
                    }
                }

                switch viewModel.state {
                case .idle, .loading:
                    LoadingView(title: L10n.text("patient.daily_tip.loading"))
                case .failed(let error):
                    ErrorBannerView(message: error.userMessage) {
                        Task { await viewModel.load() }
                    }
                case .loaded(let tip):
                    tipContent(tip)
                }
            }
            .padding(CVSpacing.lg)
        }
        .background(Color.appBackground)
        .navigationTitle(L10n.text("patient.daily_tip.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private func tipContent(_ tip: DailyTipResponse) -> some View {
        VStack(alignment: .leading, spacing: CVSpacing.lg) {
            StickerIcon(systemImage: "lightbulb.fill", size: 72, iconSize: 32, tint: .riskAttention)

            if let diagnoses = tip.diagnosesContext, !diagnoses.isEmpty {
                Text(diagnoses.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Text(tip.tipText)
                .font(CVFont.patientBody)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .cvGlossyCard(elevation: .hero, tint: .riskAttention)

            Text(L10n.text("patient.daily_tip.disclaimer"))
                .font(.footnote)
                .foregroundColor(.secondary)

            SecondaryButton(
                title: L10n.text("patient.daily_tip.listen"),
                systemImage: "speaker.wave.2.fill"
            ) {
                SpeechReminderService.shared.speakDailyTip(tip.tipText)
            }

            PrimaryButton(
                title: L10n.text("patient.daily_tip.done"),
                systemImage: "checkmark.circle.fill"
            ) {
                viewModel.markDone()
            }
        }
    }
}