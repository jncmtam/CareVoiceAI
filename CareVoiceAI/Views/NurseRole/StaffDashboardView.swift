import SwiftUI

struct StaffDashboardView: View {
    @StateObject private var viewModel = StaffDashboardViewModel()
    @State private var patientPendingDelete: PatientSummary?

    var body: some View {
        ScrollViewReader { scrollProxy in
            dashboardList(scrollProxy: scrollProxy)
        }
    }

    @ViewBuilder
    private func dashboardList(scrollProxy: ScrollViewProxy) -> some View {
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
                onSearch: { Task { await viewModel.load(notifyOnNewAlerts: false) } }
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.appBackground)

            if let overview = viewModel.overview {
                DashboardOverviewView(
                    overview: overview,
                    selectedFilter: viewModel.selectedOverviewFilter,
                    onSelectFilter: { filter in
                        Task { await viewModel.selectOverviewFilter(filter) }
                    }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.appBackground)
            }

            if viewModel.showCriticalBanner, viewModel.didTriggerCriticalHaptic, let critical = viewModel.topCriticalPatient {
                CriticalAlertBanner(patient: critical) {
                    viewModel.showCriticalBanner = false
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.appBackground)
            }

            Section(header: Text(L10n.staffPatients)) {
                Color.clear
                    .frame(height: 0)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .id("patient-list-anchor")

                if viewModel.isLoading && viewModel.displayedPatients.isEmpty {
                    LoadingView(title: L10n.loading)
                        .frame(height: 220)
                        .listRowSeparator(.hidden)
                } else if viewModel.displayedPatients.isEmpty {
                    EmptyStateView(title: L10n.text("staff.dashboard.empty"), systemImage: "person.3")
                        .frame(height: 260)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(viewModel.displayedPatients) { patient in
                        VStack(alignment: .leading, spacing: CVSpacing.md) {
                            NavigationLink(destination: PatientDetailView(patientId: patient.patientId)) {
                                PatientCard(patient: patient, showQuickDial: false, appliesCardStyle: false)
                            }
                            .buttonStyle(PlainButtonStyle())

                            PatientQuickDialRow(patient: patient)
                        }
                        .cvCard()
                        .padding(.vertical, CVSpacing.xs)
                        .pulseBorder(
                            active: patient.latestRiskLevel == .intervention,
                            color: .riskIntervention
                        )
                        .contextMenu {
                            NavigationLink(destination: PatientDetailView(patientId: patient.patientId)) {
                                Label(L10n.text("staff.patient.edit"), systemImage: "square.and.pencil")
                            }
                            Button(role: .destructive) {
                                patientPendingDelete = patient
                            } label: {
                                Label(L10n.text("common.delete"), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                patientPendingDelete = patient
                            } label: {
                                Label(L10n.text("common.delete"), systemImage: "trash")
                            }
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
        .cvDismissKeyboardOnScroll()
        .background(Color.appBackground)
        .navigationTitle(L10n.staffDashboard)
        .cvKeyboardDoneToolbar()
        .onChange(of: viewModel.selectedRiskLevel) { _ in
            guard !viewModel.suppressRiskPickerReload else { return }
            viewModel.syncOverviewFilterFromRiskPicker()
            Task { await viewModel.load(notifyOnNewAlerts: false) }
        }
        .onChange(of: viewModel.shouldScrollToPatientList) { shouldScroll in
            guard shouldScroll else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                scrollProxy.scrollTo("patient-list-anchor", anchor: .top)
            }
            viewModel.shouldScrollToPatientList = false
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CareVoiceLogoBadge(variant: .staff, size: 30)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { Task { await viewModel.load() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(L10n.retry)
            }
        }
        .task {
            viewModel.startAutoRefresh()
            await viewModel.load()
        }
        .onDisappear { viewModel.stopAutoRefresh() }
        .refreshable { await viewModel.load() }
        .alert(
            L10n.text("staff.patient.delete_confirm_title"),
            isPresented: Binding(
                get: { patientPendingDelete != nil },
                set: { if !$0 { patientPendingDelete = nil } }
            ),
            presenting: patientPendingDelete
        ) { patient in
            Button(L10n.text("common.delete"), role: .destructive) {
                Task {
                    _ = await viewModel.deletePatient(patient)
                    patientPendingDelete = nil
                }
            }
            Button(L10n.cancel, role: .cancel) {
                patientPendingDelete = nil
            }
        } message: { patient in
            Text(String(format: L10n.text("staff.patient.delete_confirm_message"), patient.fullName, patient.patientCode))
        }
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
    let selectedFilter: StaffOverviewFilter?
    let onSelectFilter: (StaffOverviewFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            Text(L10n.text("staff.dashboard.kpi"))
                .font(.headline)
            HStack(spacing: CVSpacing.sm) {
                KPIBox(
                    title: L10n.text("staff.kpi.intervention"),
                    value: "\(overview.needsInterventionToday)",
                    color: .riskIntervention,
                    isSelected: selectedFilter == .intervention,
                    action: { onSelectFilter(.intervention) }
                )
                KPIBox(
                    title: L10n.text("staff.kpi.attention"),
                    value: "\(overview.needsAttentionToday)",
                    color: .riskAttention,
                    isSelected: selectedFilter == .attention,
                    action: { onSelectFilter(.attention) }
                )
                KPIBox(
                    title: L10n.text("staff.kpi.total"),
                    value: "\(overview.totalActivePatients)",
                    color: .careVoicePrimary,
                    isSelected: selectedFilter == .all,
                    action: { onSelectFilter(.all) }
                )
            }
            HStack(spacing: CVSpacing.sm) {
                KPIBox(
                    title: L10n.text("staff.kpi.checkin_rate"),
                    value: "\(Int((overview.checkinCompletionRate * 100).rounded()))%",
                    color: .riskNormal,
                    action: {}
                )
                KPIBox(
                    title: L10n.text("staff.kpi.pending_ocr"),
                    value: "\(overview.pendingOcrJobs ?? 0)",
                    color: .riskAttention,
                    action: {}
                )
                KPIBox(
                    title: L10n.text("staff.kpi.pending_analysis"),
                    value: "\(overview.pendingAnalysisJobs ?? 0)",
                    color: .careVoicePrimary,
                    action: {}
                )
            }
        }
        .cvCard()
    }
}

private struct KPIBox: View {
    let title: String
    let value: String
    let color: Color
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
            .background(color.opacity(isSelected ? 0.22 : 0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 2)
            )
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
