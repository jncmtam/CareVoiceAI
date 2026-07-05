import SwiftUI

struct NewPatientView: View {
    @StateObject private var viewModel = NewPatientViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CVSpacing.lg) {
                SectionHeaderView(
                    title: L10n.newPatient,
                    systemImage: "person.badge.plus",
                    subtitle: L10n.text("staff.new_patient.subtitle")
                )

                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage)
                }

                if let success = viewModel.successMessage {
                    HStack(spacing: CVSpacing.md) {
                        StickerIcon(systemImage: "checkmark.seal.fill", size: 40, iconSize: 18, tint: .riskNormal)
                        Text(success)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .cvGlossyCard(tint: .riskNormal)
                }

                VStack(spacing: CVSpacing.md) {
                    HStack(spacing: CVSpacing.md) {
                        StickerIcon(systemImage: "barcode.viewfinder", size: 40, iconSize: 18, tint: .careVoicePrimary)
                        Text(L10n.text("staff.new_patient.code_auto"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FormField(
                        title: L10n.text("patient.full_name"),
                        text: $viewModel.fullName,
                        systemImage: "person.fill",
                        errorMessage: viewModel.fieldErrors[.fullName]
                    )
                    FormField(
                        title: L10n.phoneNumber,
                        text: $viewModel.phoneNumber,
                        systemImage: "phone.fill",
                        hint: L10n.text("validation.phone.hint"),
                        errorMessage: viewModel.fieldErrors[.phoneNumber],
                        keyboardType: .phonePad
                    )
                    FormField(
                        title: L10n.text("patient.caregiver_name"),
                        text: $viewModel.caregiverName,
                        systemImage: "person.2.fill"
                    )
                    FormField(
                        title: L10n.text("patient.caregiver_phone"),
                        text: $viewModel.caregiverPhone,
                        systemImage: "phone.badge.waveform.fill",
                        hint: L10n.text("validation.phone.optional_hint"),
                        errorMessage: viewModel.fieldErrors[.caregiverPhone],
                        keyboardType: .phonePad
                    )
                    FormField(
                        title: L10n.text("patient.diagnoses"),
                        text: $viewModel.diagnosisText,
                        systemImage: "heart.text.square.fill",
                        hint: L10n.text("staff.new_patient.diagnoses_hint")
                    )

                    VStack(alignment: .leading, spacing: CVSpacing.sm) {
                        StickerLabel(text: L10n.text("patient.notes"), systemImage: "note.text")
                        TextEditor(text: $viewModel.notes)
                            .frame(minHeight: 110)
                            .padding(CVSpacing.sm)
                            .background(Color.appSurface)
                            .cornerRadius(CVCornerRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: CVCornerRadius.sm)
                                    .stroke(Color.careVoicePrimary.opacity(0.14), lineWidth: 1)
                            )
                    }
                }
                .cvGlossyCard()

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
        .cvDismissKeyboardOnScroll()
        .background(Color.appBackground)
        .navigationTitle(L10n.newPatient)
        .cvKeyboardDoneToolbar()
    }
}