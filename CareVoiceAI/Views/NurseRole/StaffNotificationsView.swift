import SwiftUI

@available(iOS 16.0, *)
struct StaffNotificationsView: View {
    @ObservedObject var viewModel: StaffNotificationsViewModel

    var body: some View {
        List {
            if let error = viewModel.error {
                ErrorBannerView(message: error.userMessage) {
                    Task { await viewModel.load() }
                }
                .listRowSeparator(.hidden)
            }

            if viewModel.isLoading && viewModel.items.isEmpty {
                LoadingView(title: L10n.loading)
                    .frame(height: 220)
                    .listRowSeparator(.hidden)
            } else if viewModel.items.isEmpty {
                EmptyStateView(
                    title: L10n.text("staff.notifications.empty"),
                    systemImage: "bell.slash"
                )
                .frame(height: 260)
                .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.items) { item in
                    NavigationLink {
                        PatientDetailView(patientId: item.patientId)
                    } label: {
                        StaffNotificationRow(item: item)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowBackground(Color.appBackground)
                    .onAppear {
                        Task { await viewModel.markRead(item) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color.appBackground)
        .navigationTitle(L10n.text("staff.notifications.title"))
        .toolbar {
            if viewModel.unreadCount > 0 {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.text("staff.notifications.mark_all_read")) {
                        Task { await viewModel.markAllRead() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .refreshable {
            await viewModel.load()
        }
        .task {
            await viewModel.load(notifyOnNew: true)
        }

    }
}

private struct StaffNotificationRow: View {
    let item: StaffNotificationItem

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.patientName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.careVoicePrimary)
                }
                Spacer()
                if item.unread {
                    Circle()
                        .fill(Color.careVoicePrimary)
                        .frame(width: 10, height: 10)
                }
            }

            HStack(spacing: CVSpacing.sm) {
                if let previous = item.previousRiskLevel {
                    RiskBadge(level: previous)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                }
                RiskBadge(level: item.newRiskLevel)
            }

            Text(item.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(DateFormatters.shortDateTime.string(from: item.createdAt))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, CVSpacing.xs)
    }
}
