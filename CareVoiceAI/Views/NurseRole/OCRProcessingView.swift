import SwiftUI

struct OCRProcessingView: View {
    let patientId: String
    @StateObject private var viewModel: OCRProcessingViewModel

    init(patientId: String, jobId: String) {
        self.patientId = patientId
        _viewModel = StateObject(wrappedValue: OCRProcessingViewModel(jobId: jobId))
    }

    var body: some View {
        VStack(spacing: CVSpacing.xl) {
            if let error = viewModel.error {
                ErrorBannerView(message: error.userMessage) {
                    Task { await viewModel.startPolling() }
                }
            }

            PollingStatusView(
                title: viewModel.job.map { L10n.jobStatus($0.status) } ?? L10n.processingOCR,
                progress: viewModel.job?.progress
            )

            Text(L10n.text("staff.ocr.background_note"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let job = viewModel.job, job.status == .needsReview {
                NavigationLink(destination: OCRReviewView(patientId: patientId, job: job)) {
                    Label(L10n.confirmOCR, systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(CVButtonStyle(kind: .primary))
            }

            DestructiveButton(title: L10n.cancel, systemImage: "xmark.circle.fill") {
                Task { await viewModel.cancel() }
            }

            Spacer()
        }
        .padding(CVSpacing.lg)
        .background(Color.appBackground)
        .navigationTitle(L10n.processingOCR)
        .task { await viewModel.startPolling() }
    }
}
