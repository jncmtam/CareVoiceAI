import SwiftUI

struct StaffDashboardView: View {
    @StateObject private var viewModel = StaffDashboardViewModel()

    var body: some View {
        List {
            if let error = viewModel.error {
                ErrorBannerView(message: error.userMessage) {
                    Task { await viewModel.load() }
                }
                .listRowSeparator(.hidden)
            }

            StaffDashboardFilterView(
                query: $viewModel.query,
                selectedRiskLevel: $viewModel.selectedRiskLevel,
                onSearch: { Task { await viewModel.load() } }
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.appBackground)

            if let overview = viewModel.overview {
                DashboardOverviewView(overview: overview)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.appBackground)
            }

            Section(header: Text(L10n.staffPatients)) {
                if viewModel.isLoading && viewModel.patients.isEmpty {
                    LoadingView(title: L10n.loading)
                        .frame(height: 220)
                        .listRowSeparator(.hidden)
                } else if viewModel.patients.isEmpty {
                    EmptyStateView(title: L10n.text("staff.dashboard.empty"), systemImage: "person.3")
                        .frame(height: 260)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(viewModel.patients) { patient in
                        NavigationLink(destination: PatientDetailView(patientId: patient.patientId)) {
                            PatientCard(patient: patient)
                                .padding(.vertical, CVSpacing.xs)
                        }
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(current: patient) }
                        }
                    }
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .background(Color.appBackground)
        .navigationTitle(L10n.staffDashboard)
        .onChange(of: viewModel.selectedRiskLevel) { _ in
            Task { await viewModel.load() }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { Task { await viewModel.load() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(L10n.retry)
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }
}

private struct StaffDashboardFilterView: View {
    @Binding var query: String
    @Binding var selectedRiskLevel: RiskLevel?
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            HStack(spacing: CVSpacing.sm) {
                TextField(L10n.text("staff.search.placeholder"), text: $query)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .submitLabel(.search)
                    .onSubmit(onSearch)

                if !query.cvTrimmed.isEmpty {
                    Button(action: {
                        query = ""
                        onSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(L10n.text("common.clear"))
                }

                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.careVoicePrimary)
                .accessibilityLabel(L10n.text("staff.search"))
            }

            Picker(L10n.text("staff.filter.risk"), selection: $selectedRiskLevel) {
                Text(L10n.text("staff.filter.all")).tag(nil as RiskLevel?)
                Text(L10n.text("staff.filter.intervention_short")).tag(RiskLevel.intervention as RiskLevel?)
                Text(L10n.text("staff.filter.attention_short")).tag(RiskLevel.attention as RiskLevel?)
                Text(L10n.text("staff.filter.normal_short")).tag(RiskLevel.normal as RiskLevel?)
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding(.vertical, CVSpacing.sm)
    }
}

private struct DashboardOverviewView: View {
    let overview: DashboardOverview

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            Text(L10n.text("staff.dashboard.kpi"))
                .font(.headline)
            HStack(spacing: CVSpacing.sm) {
                KPIBox(title: L10n.text("staff.kpi.total"), value: "\(overview.totalActivePatients)", color: .careVoicePrimary)
                KPIBox(title: L10n.text("staff.kpi.attention"), value: "\(overview.needsAttentionToday)", color: .riskAttention)
                KPIBox(title: L10n.text("staff.kpi.intervention"), value: "\(overview.needsInterventionToday)", color: .riskIntervention)
            }
            KPIBox(
                title: L10n.text("staff.kpi.completion"),
                value: "\(Int((overview.checkinCompletionRate * 100).rounded()))%",
                color: .riskNormal
            )
        }
        .cvCard()
    }
}

private struct KPIBox: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.xs) {
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(CVSpacing.sm)
        .background(color.opacity(0.10))
        .cornerRadius(8)
    }
}
