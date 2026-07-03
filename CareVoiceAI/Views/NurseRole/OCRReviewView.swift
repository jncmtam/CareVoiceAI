import SwiftUI

struct OCRReviewView: View {
    @StateObject private var viewModel: OCRReviewViewModel
    @Environment(\.presentationMode) private var presentationMode

    init(patientId: String, job: OCRJobResponse) {
        _viewModel = StateObject(wrappedValue: OCRReviewViewModel(patientId: patientId, job: job))
    }

    var body: some View {
        List {
            if let error = viewModel.error {
                ErrorBannerView(message: error.userMessage)
            }

            Section(header: Text(L10n.medications)) {
                ForEach(viewModel.medications.indices, id: \.self) { index in
                    OCRMedicationEditor(medication: $viewModel.medications[index])
                }
                .onDelete(perform: viewModel.removeMedication)

                Button(action: viewModel.addMedication) {
                    Label(L10n.text("medications.add"), systemImage: "plus.circle.fill")
                }
            }

            Section(header: Text(L10n.text("staff.note"))) {
                TextEditor(text: $viewModel.nurseNote)
                    .frame(minHeight: 110)
            }

            Section {
                PrimaryButton(
                    title: L10n.confirmOCR,
                    systemImage: "checkmark.seal.fill",
                    isLoading: viewModel.isSaving,
                    isDisabled: viewModel.medications.allSatisfy { $0.name.cvTrimmed.isEmpty }
                ) {
                    Task { await viewModel.confirm() }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle(L10n.confirmOCR)
        .alert(isPresented: $viewModel.didSave) {
            Alert(
                title: Text(L10n.text("staff.ocr.saved")),
                message: Text(L10n.text("staff.ocr.saved_message")),
                dismissButton: .default(Text(L10n.continueText)) {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

private struct OCRMedicationEditor: View {
    @Binding var medication: OCRDraftMedication

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            TextField(L10n.text("medication.name"), text: $medication.name)
            TextField(L10n.text("medication.strength"), text: optionalBinding(\.strength))
            TextField(L10n.text("medication.dosage"), text: optionalBinding(\.dosage))
            TextField(L10n.text("medication.frequency"), text: optionalBinding(\.frequency))
            TextField(L10n.text("medication.instructions"), text: optionalBinding(\.instructions))
            if let confidence = medication.confidence {
                Text(String(format: L10n.text("ocr.confidence"), Int(confidence * 100)))
                    .font(.caption)
                    .foregroundColor(confidence < 0.75 ? .riskAttention : .secondary)
            }
        }
        .padding(.vertical, CVSpacing.sm)
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<OCRDraftMedication, String?>) -> Binding<String> {
        Binding<String>(
            get: { medication[keyPath: keyPath] ?? "" },
            set: { medication[keyPath: keyPath] = $0.cvNilIfEmpty }
        )
    }
}
