import SwiftUI

struct StaffLoginView: View {
    @StateObject private var viewModel = StaffLoginViewModel()
    @State private var appeared = false

    var body: some View {
        ZStack {
            AuthDecorBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: CVSpacing.lg) {
                    AuthLoginHeader(title: L10n.staffLoginTitle, logoVariant: .staff)

                    if let error = viewModel.error {
                        ErrorBannerView(message: error.userMessage)
                            .cvStaggeredAppear(index: 1, isVisible: appeared)
                    }

                    VStack(spacing: CVSpacing.md) {
                        FormField(
                            title: L10n.emailOrStaffCode,
                            text: $viewModel.login,
                            systemImage: "person.badge.key.fill"
                        )
                        FormField(
                            title: L10n.password,
                            text: $viewModel.password,
                            systemImage: "lock.fill",
                            isSecure: true
                        )
                    }
                    .cvGlossyCard(elevation: .raised)
                    .cvStaggeredAppear(index: 3, isVisible: appeared)

                    PrimaryButton(
                        title: L10n.login,
                        systemImage: "arrow.right.circle.fill",
                        isLoading: viewModel.isLoading,
                        isDisabled: !viewModel.canSubmit
                    ) {
                        Task { await viewModel.submit() }
                    }
                    .cvStaggeredAppear(index: 4, isVisible: appeared)
                }
                .padding(CVSpacing.lg)
            }
            .cvDismissKeyboardOnScroll()
        }
        .navigationTitle(L10n.roleStaff)
        .navigationBarTitleDisplayMode(.inline)
        .cvKeyboardDoneToolbar()
        .onAppear { appeared = true }
    }
}