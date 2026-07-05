import SwiftUI

struct CheckinHistoryView: View {
    @StateObject private var viewModel = CheckinHistoryViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                LoadingView(title: L10n.loading)
            } else if let error = viewModel.error, viewModel.items.isEmpty {
                ErrorBannerView(message: error.userMessage) {
                    Task { await viewModel.load() }
                }
                .padding(CVSpacing.lg)
            } else if viewModel.items.isEmpty {
                EmptyStateView(title: L10n.text("history.empty"), systemImage: "clock")
            } else {
                List(viewModel.items) { item in
                    VStack(alignment: .leading, spacing: CVSpacing.sm) {
                        HStack {
                            Text(DateFormatters.shortDateTime.string(from: item.checkedInAt))
                                .font(.headline)
                            Spacer()
                            RiskBadge(level: item.riskLevel)
                        }
                        Text(item.patientMessage ?? L10n.text("patient.checkin.sent"))
                            .font(CVFont.patientBody)
                        if let summary = item.summaryForPatient {
                            Text(summary)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        if let staffNote = item.staffNote, !staffNote.isEmpty {
                            VStack(alignment: .leading, spacing: CVSpacing.xs) {
                                Label(L10n.text("patient.history.staff_note_title"), systemImage: "heart.text.square.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.careVoicePrimary)
                                Text(staffNote)
                                    .font(CVFont.patientBody)
                                    .foregroundColor(.primary)
                            }
                            .padding(CVSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.careVoicePrimary.opacity(0.08))
                            .cornerRadius(CVCornerRadius.sm)
                        }
                    }
                    .padding(.vertical, CVSpacing.sm)
                }
                .listStyle(PlainListStyle())
                .cvDismissKeyboardOnScroll()
                .refreshable { await viewModel.load() }
            }
        }
        .navigationTitle(L10n.history)
        .task { await viewModel.load() }
    }
}
