import SwiftUI

struct PatientLoginView: View {
    @StateObject private var viewModel = PatientLoginViewModel()
    @State private var appeared = false

    var body: some View {
        ZStack {
            AuthDecorBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: CVSpacing.lg) {
                    AuthLoginHeader(title: L10n.patientLoginTitle, logoVariant: .patient)

                    if let error = viewModel.error {
                        ErrorBannerView(message: error.userMessage)
                            .cvStaggeredAppear(index: 1, isVisible: appeared)
                    }

                    passwordLoginForm

                    switch viewModel.step {
                    case .enterPhone:
                        otpRequestForm
                        Divider()
                            .padding(.vertical, CVSpacing.xs)
                        codeLoginForm
                    case .enterOTP(_, let maskedPhone):
                        otpVerifyForm(maskedPhone: maskedPhone)
                    }
                }
                .padding(CVSpacing.lg)
            }
            .cvDismissKeyboardOnScroll()
        }
        .navigationTitle(L10n.rolePatient)
        .navigationBarTitleDisplayMode(.inline)
        .cvKeyboardDoneToolbar()
        .onAppear { appeared = true }
    }

    private var passwordLoginForm: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.login,
                systemImage: "person.fill"
            )
            FormField(
                title: L10n.text("auth.account"),
                text: $viewModel.login,
                systemImage: "person.crop.circle"
            )
            FormField(
                title: L10n.password,
                text: $viewModel.password,
                systemImage: "lock.fill",
                isSecure: true
            )
            PrimaryButton(
                title: L10n.login,
                systemImage: "arrow.right.circle.fill",
                isLoading: viewModel.isLoading,
                isDisabled: !viewModel.canSubmitPasswordLogin
            ) {
                Task { await viewModel.loginWithPassword() }
            }
        }
        .cvGlossyCard()
        .cvStaggeredAppear(index: 2, isVisible: appeared)
    }

    private var otpRequestForm: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.requestOTP,
                systemImage: "message.fill",
                subtitle: L10n.text("auth.otp_section_hint")
            )
            FormField(
                title: L10n.phoneNumber,
                text: $viewModel.phoneNumber,
                systemImage: "phone.fill",
                keyboardType: .phonePad
            )
            FormField(
                title: L10n.patientCode,
                text: $viewModel.patientCode,
                systemImage: "barcode.viewfinder"
            )
            PrimaryButton(
                title: L10n.requestOTP,
                systemImage: "paperplane.fill",
                isLoading: viewModel.isLoading,
                isDisabled: viewModel.phoneNumber.cvTrimmed.isEmpty
            ) {
                Task { await viewModel.requestOTP() }
            }
        }
        .cvGlossyCard()
        .cvStaggeredAppear(index: 3, isVisible: appeared)
    }

    private func otpVerifyForm(maskedPhone: String) -> some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.verifyOTP,
                systemImage: "checkmark.shield.fill",
                subtitle: String(format: L10n.text("auth.otp_sent_to"), maskedPhone)
            )
            FormField(
                title: L10n.otpCode,
                text: $viewModel.otpCode,
                systemImage: "number.circle.fill",
                keyboardType: .numberPad
            )
            PrimaryButton(
                title: L10n.verifyOTP,
                systemImage: "checkmark.circle.fill",
                isLoading: viewModel.isLoading,
                isDisabled: viewModel.otpCode.cvTrimmed.isEmpty
            ) {
                Task { await viewModel.verifyOTP() }
            }
            SecondaryButton(title: L10n.text("auth.change_phone"), systemImage: "arrow.left") {
                viewModel.step = .enterPhone
            }
        }
        .cvGlossyCard()
        .cvStaggeredAppear(index: 3, isVisible: appeared)
    }

    private var codeLoginForm: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.loginWithPatientCode,
                systemImage: "person.text.rectangle",
                subtitle: L10n.text("auth.code_section_hint")
            )
            FormField(
                title: L10n.patientCode,
                text: $viewModel.patientCode,
                systemImage: "barcode.viewfinder"
            )
            FormField(
                title: L10n.text("auth.phone_last4"),
                text: $viewModel.phoneLast4,
                systemImage: "phone.badge.checkmark",
                keyboardType: .numberPad
            )
            SecondaryButton(
                title: L10n.loginWithPatientCode,
                systemImage: "person.text.rectangle",
                isDisabled: viewModel.patientCode.cvTrimmed.isEmpty || viewModel.phoneLast4.cvTrimmed.isEmpty
            ) {
                Task { await viewModel.loginWithCode() }
            }
        }
        .cvGlossyCard()
        .cvStaggeredAppear(index: 4, isVisible: appeared)
    }
}