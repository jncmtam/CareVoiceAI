import SwiftUI

struct BackendSetupView: View {
    @StateObject private var viewModel = BackendSetupViewModel()

    var body: some View {
        List {
            Section(header: Text(L10n.text("settings.connection"))) {
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
    @Published var apiBaseURL = APIClient.shared.baseURL.absoluteString
    @Published var errorMessage: String?

    func load() {
        apiBaseURL = APIClient.shared.baseURL.absoluteString
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