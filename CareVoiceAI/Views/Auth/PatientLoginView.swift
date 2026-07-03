import SwiftUI

struct PatientLoginView: View {
    @StateObject private var viewModel = PatientLoginViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CVSpacing.lg) {
                Text(L10n.patientLoginTitle)
                    .font(CVFont.patientTitle)
                    .foregroundColor(.primary)
                    .padding(.top, CVSpacing.lg)

                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage)
                }

                switch viewModel.step {
                case .enterPhone:
                    otpRequestForm
                    Divider()
                    codeLoginForm
                case .enterOTP(_, let maskedPhone):
                    otpVerifyForm(maskedPhone: maskedPhone)
                }
            }
            .padding(CVSpacing.lg)
        }
        .background(Color.appBackground)
        .navigationTitle(L10n.rolePatient)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var otpRequestForm: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            FormField(title: L10n.phoneNumber, text: $viewModel.phoneNumber, keyboardType: .phonePad)
            FormField(title: L10n.patientCode, text: $viewModel.patientCode)
            PrimaryButton(
                title: L10n.requestOTP,
                systemImage: "message.fill",
                isLoading: viewModel.isLoading,
                isDisabled: viewModel.phoneNumber.cvTrimmed.isEmpty
            ) {
                Task { await viewModel.requestOTP() }
            }
        }
    }

    private func otpVerifyForm(maskedPhone: String) -> some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            Text(String(format: L10n.text("auth.otp_sent_to"), maskedPhone))
                .font(CVFont.patientBody)
                .foregroundColor(.secondary)
            FormField(title: L10n.otpCode, text: $viewModel.otpCode, keyboardType: .numberPad)
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
    }

    private var codeLoginForm: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            Text(L10n.loginWithPatientCode)
                .font(.headline)
            FormField(title: L10n.patientCode, text: $viewModel.patientCode)
            FormField(title: L10n.text("auth.phone_last4"), text: $viewModel.phoneLast4, keyboardType: .numberPad)
            SecondaryButton(
                title: L10n.loginWithPatientCode,
                systemImage: "person.text.rectangle",
                isDisabled: viewModel.patientCode.cvTrimmed.isEmpty || viewModel.phoneLast4.cvTrimmed.isEmpty
            ) {
                Task { await viewModel.loginWithCode() }
            }
            if AppConstants.isDemoMode {
                SecondaryButton(title: L10n.text("auth.demo_patient"), systemImage: "play.circle.fill") {
                    Task { await viewModel.loginDemoPatient() }
                }
            }
        }
    }
}
