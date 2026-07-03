import SwiftUI

struct FaceVerificationPlaceholderView: View {
    @StateObject private var viewModel = FaceVerificationViewModel()

    var body: some View {
        VStack(spacing: CVSpacing.xl) {
            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundColor(.careVoicePrimary)
            Text(L10n.text("face.title"))
                .font(CVFont.patientTitle)
                .multilineTextAlignment(.center)
            Text(L10n.text("face.subtitle"))
                .font(CVFont.patientBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let error = viewModel.error {
                ErrorBannerView(message: error.userMessage)
            }
            if let status = viewModel.statusText {
                PollingStatusView(title: status, progress: nil)
            }

            PrimaryButton(
                title: L10n.text("face.start"),
                systemImage: "faceid",
                isLoading: viewModel.isLoading
            ) {
                Task { await viewModel.start() }
            }
        }
        .padding(CVSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .navigationTitle(L10n.text("face.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
