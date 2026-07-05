import SwiftUI

struct DocumentUploadView: View {
    let patientId: String
    @StateObject private var viewModel: DocumentUploadViewModel
    @State private var isShowingPicker = false
    @State private var navigateToProcessing = false

    init(patientId: String) {
        self.patientId = patientId
        _viewModel = StateObject(wrappedValue: DocumentUploadViewModel(patientId: patientId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.lg) {
            if let error = viewModel.error {
                ErrorBannerView(message: error.userMessage)
            }

            VStack(alignment: .leading, spacing: CVSpacing.md) {
                SectionHeaderView(
                    title: L10n.uploadDocument,
                    systemImage: "doc.text.viewfinder",
                    subtitle: L10n.text("document.upload_hint")
                )
                Picker(L10n.text("document.type"), selection: $viewModel.documentType) {
                    Text(L10n.text("document.prescription")).tag(DocumentType.prescription)
                    Text(L10n.text("document.discharge_note")).tag(DocumentType.dischargeNote)
                }
                Picker(L10n.text("document.ocr_mode"), selection: $viewModel.ocrMode) {
                    Text(L10n.text("ocr.auto")).tag(OcrMode.auto)
                    Text(L10n.text("ocr.basic")).tag(OcrMode.basic)
                    Text(L10n.text("ocr.table")).tag(OcrMode.table)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .cvCard()

            SecondaryButton(title: L10n.text("document.choose_file"), systemImage: "doc.badge.plus") {
                isShowingPicker = true
            }

            if let selected = viewModel.selectedFileURL {
                Label(selected.lastPathComponent, systemImage: "doc.fill")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            PrimaryButton(
                title: L10n.uploadDocument,
                systemImage: "icloud.and.arrow.up.fill",
                isLoading: viewModel.isUploading,
                isDisabled: viewModel.selectedFileURL == nil
            ) {
                Task {
                    await viewModel.upload()
                    if viewModel.uploadResponse != nil {
                        navigateToProcessing = true
                    }
                }
            }

            if let response = viewModel.uploadResponse {
                NavigationLink(
                    destination: OCRProcessingView(patientId: patientId, jobId: response.jobId),
                    isActive: $navigateToProcessing
                ) {
                    EmptyView()
                }
                .hidden()

                NavigationLink(destination: OCRProcessingView(patientId: patientId, jobId: response.jobId)) {
                    Label(L10n.processingOCR, systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(CVButtonStyle(kind: .primary))
            }

            Spacer()
        }
        .padding(CVSpacing.lg)
        .background(Color.appBackground)
        .navigationTitle(L10n.uploadDocument)
        .sheet(isPresented: $isShowingPicker) {
            DocumentPickerView { url in
                viewModel.selectedFileURL = url
                isShowingPicker = false
            }
        }
    }
}
