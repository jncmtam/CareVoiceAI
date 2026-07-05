import SwiftUI

struct OCRReviewView: View {
    @StateObject private var viewModel: OCRReviewViewModel
    @Environment(\.presentationMode) private var presentationMode
    @State private var showRawText = false

    init(patientId: String, job: OCRJobResponse) {
        _viewModel = StateObject(wrappedValue: OCRReviewViewModel(patientId: patientId, job: job))
    }

    var body: some View {
        List {
            if let error = viewModel.error {
                ErrorBannerView(message: error.userMessage)
            }

            if !viewModel.warnings.isEmpty {
                Section(header: Text(L10n.text("ocr.review.warnings"))) {
                    ForEach(viewModel.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundColor(.riskAttention)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section(
                header: Text(L10n.text("ocr.review.patient")),
                footer: Text(L10n.text("ocr.review.edit_hint"))
            ) {
                TextField(L10n.text("patient.full_name"), text: $viewModel.patientFullName)
                TextField(L10n.phoneNumber, text: $viewModel.patientPhone)
                    .keyboardType(.phonePad)
                TextField(L10n.text("patient.diagnoses"), text: $viewModel.patientDiagnoses)
                TextField(L10n.text("patient.address"), text: $viewModel.patientAddress)
            }

            Section(header: Text(L10n.text("ocr.review.doctor"))) {
                TextField(L10n.text("ocr.review.examining_doctor"), text: $viewModel.examiningDoctor)
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

            Section(header: Text(L10n.text("ocr.review.follow_up"))) {
                Toggle(L10n.text("ocr.review.has_follow_up"), isOn: $viewModel.hasFollowUpDate)
                if viewModel.hasFollowUpDate {
                    DatePicker(
                        L10n.text("ocr.review.appointment_date"),
                        selection: $viewModel.followUpDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                TextField(L10n.text("ocr.review.department"), text: $viewModel.followUpDepartment)
                TextField(L10n.text("ocr.review.follow_up_doctor"), text: $viewModel.followUpDoctor)
            }

            Section(header: Text(L10n.text("ocr.review.instructions"))) {
                TextEditor(text: $viewModel.instructions)
                    .frame(minHeight: 100)
            }

            Section(header: Text(L10n.text("staff.note"))) {
                TextEditor(text: $viewModel.nurseNote)
                    .frame(minHeight: 90)
            }

            if !viewModel.rawText.isEmpty {
                Section(header: Text(L10n.text("ocr.review.raw_text"))) {
                    Button {
                        showRawText.toggle()
                    } label: {
                        Label(
                            showRawText ? L10n.text("ocr.review.hide_raw") : L10n.text("ocr.review.show_raw"),
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                    if showRawText {
                        Text(viewModel.rawText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
        .cvDismissKeyboardOnScroll()
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