import SwiftUI

struct FaceVerificationPlaceholderView: View {
    @StateObject private var viewModel = FaceVerificationViewModel()
    @State private var showCamera = false

    var body: some View {
        VStack(spacing: CVSpacing.xl) {
            StickerIcon(systemImage: "faceid", size: 72, iconSize: 32, tint: .careVoicePrimary)
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
            if viewModel.isVerified {
                Label(L10n.text("face.verified"), systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundColor(.riskNormal)
            }

            if viewModel.sessionId == nil {
                PrimaryButton(
                    title: L10n.text("face.start"),
                    systemImage: "faceid",
                    isLoading: viewModel.isLoading
                ) {
                    Task { await viewModel.start() }
                }
            } else if !viewModel.isVerified {
                PrimaryButton(
                    title: L10n.text("face.capture"),
                    systemImage: "camera.fill",
                    isLoading: viewModel.isLoading,
                    isDisabled: viewModel.isLoading
                ) {
                    showCamera = true
                }
            }
        }
        .padding(CVSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .navigationTitle(L10n.text("face.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCamera) {
            CameraCaptureView(
                onCapture: { image in
                    showCamera = false
                    Task { await viewModel.upload(image: image) }
                },
                onCancel: { showCamera = false }
            )
        }
    }
}
