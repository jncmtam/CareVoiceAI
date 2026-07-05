import SwiftUI

struct BackendSetupView: View {
    @StateObject private var viewModel = BackendSetupViewModel()

    var body: some View {
        List {
            Section(header: Text(L10n.text("settings.connection"))) {
                Toggle(L10n.text("settings.demo_mode"), isOn: $viewModel.isDemoMode)
                    .onChange(of: viewModel.isDemoMode) { enabled in
                        viewModel.updateDemoMode(enabled)
                    }

                if viewModel.isDemoMode {
                    Text(L10n.text("settings.demo_mode_on_hint"))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    TextField(L10n.text("settings.api_base_url"), text: $viewModel.apiBaseURL)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button {
                        Task { await viewModel.save() }
                    } label: {
                        Label(L10n.text("settings.api_save"), systemImage: "externaldrive.badge.checkmark")
                    }
                    .disabled(viewModel.apiBaseURL.cvTrimmed.isEmpty)
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    ErrorBannerView(message: error)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle(L10n.text("settings.connection"))
        .task {
            viewModel.load()
        }
    }
}

@MainActor
final class BackendSetupViewModel: ObservableObject {
    @Published var isDemoMode = AppConstants.isDemoMode
    @Published var apiBaseURL = APIClient.shared.baseURL.absoluteString
    @Published var errorMessage: String?

    func load() {
        isDemoMode = AppConstants.isDemoMode
        apiBaseURL = APIClient.shared.baseURL.absoluteString
    }

    func updateDemoMode(_ enabled: Bool) {
        AppConstants.isDemoMode = enabled
        isDemoMode = enabled
        errorMessage = nil
    }

    func save() async {
        errorMessage = nil
        guard let normalized = APIBaseURLNormalizer.normalize(apiBaseURL) else {
            errorMessage = L10n.text("settings.api_invalid")
            return
        }
        AppConstants.apiBaseURL = normalized
        apiBaseURL = normalized
        HapticsManager.success()
    }
}