import SwiftUI

struct StaffLoginView: View {
    @StateObject private var viewModel = StaffLoginViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CVSpacing.lg) {
                Text(L10n.staffLoginTitle)
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.primary)
                    .padding(.top, CVSpacing.lg)

                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage)
                }

                FormField(title: L10n.emailOrStaffCode, text: $viewModel.login)
                FormField(title: L10n.password, text: $viewModel.password, isSecure: true)

                PrimaryButton(
                    title: L10n.login,
                    systemImage: "arrow.right.circle.fill",
                    isLoading: viewModel.isLoading,
                    isDisabled: !viewModel.canSubmit
                ) {
                    Task { await viewModel.submit() }
                }

                if AppConstants.isDemoMode {
                    SecondaryButton(title: L10n.text("auth.demo_staff"), systemImage: "play.circle.fill") {
                        Task { await viewModel.submitDemo() }
                    }
                }
            }
            .padding(CVSpacing.lg)
        }
        .background(Color.appBackground)
        .navigationTitle(L10n.roleStaff)
        .navigationBarTitleDisplayMode(.inline)
    }
}
