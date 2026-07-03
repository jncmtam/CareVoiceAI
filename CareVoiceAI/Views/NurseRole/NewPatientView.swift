import SwiftUI

struct NewPatientView: View {
    @StateObject private var viewModel = NewPatientViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CVSpacing.lg) {
                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage)
                }

                FormField(title: L10n.patientCode, text: $viewModel.patientCode)
                FormField(title: L10n.text("patient.full_name"), text: $viewModel.fullName)
                FormField(title: L10n.phoneNumber, text: $viewModel.phoneNumber, keyboardType: .phonePad)
                FormField(title: L10n.text("patient.caregiver_name"), text: $viewModel.caregiverName)
                FormField(title: L10n.text("patient.caregiver_phone"), text: $viewModel.caregiverPhone, keyboardType: .phonePad)
                FormField(title: L10n.text("patient.diagnoses"), text: $viewModel.diagnosisText)

                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(L10n.text("patient.notes"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    TextEditor(text: $viewModel.notes)
                        .frame(minHeight: 110)
                        .padding(CVSpacing.sm)
                        .background(Color.appSurface)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                }

                PrimaryButton(
                    title: L10n.newPatient,
                    systemImage: "person.badge.plus",
                    isLoading: viewModel.isLoading,
                    isDisabled: !viewModel.canSubmit
                ) {
                    Task { await viewModel.submit() }
                }

                if let createdPatient = viewModel.createdPatient {
                    NavigationLink(destination: DocumentUploadView(patientId: createdPatient.id)) {
                        Label(L10n.uploadDocument, systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(CVButtonStyle(kind: .primary))
                }
            }
            .padding(CVSpacing.lg)
        }
        .background(Color.appBackground)
        .navigationTitle(L10n.newPatient)
    }
}
