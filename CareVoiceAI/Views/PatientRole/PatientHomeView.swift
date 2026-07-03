import SwiftUI

struct PatientHomeView: View {
    @StateObject private var viewModel = PatientHomeViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CVSpacing.lg) {
                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage) {
                        Task { await viewModel.load() }
                    }
                }

                checkinCard
                medicationPreview
                appointmentPreview

                NavigationLink(destination: FaceVerificationPlaceholderView()) {
                    Label(L10n.text("face.title"), systemImage: "faceid")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(CVButtonStyle(kind: .secondary))
            }
            .padding(CVSpacing.lg)
        }
        .background(Color.appBackground)
        .navigationTitle(L10n.patientHomeTitle)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var checkinCard: some View {
        switch viewModel.checkinState {
        case .idle, .loading:
            LoadingView(title: L10n.preparingQuestion)
                .frame(minHeight: 220)
                .cvCard()
        case .failed(let error):
            ErrorBannerView(message: error.userMessage) {
                Task { await viewModel.load() }
            }
        case .empty(let message):
            EmptyStateView(title: message)
                .frame(minHeight: 220)
        case .loaded(let checkin):
            VStack(alignment: .leading, spacing: CVSpacing.lg) {
                HStack {
                    Label(L10n.todayCheckin, systemImage: "heart.text.square.fill")
                        .font(CVFont.patientAction)
                        .foregroundColor(.careVoicePrimary)
                    Spacer()
                    if checkin.audioStatus == .generating {
                        RiskBadge(level: nil)
                    }
                }
                Text(checkin.questionText)
                    .font(CVFont.patientBody)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink(destination: TodayCheckinView()) {
                    Label(L10n.continueText, systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(CVButtonStyle(kind: .primary))
            }
            .cvCard()
        }
    }

    private var medicationPreview: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            HStack {
                Text(L10n.medications)
                    .font(.headline)
                Spacer()
                NavigationLink(L10n.text("common.view_all"), destination: MedicationListView())
                    .font(.caption.weight(.semibold))
            }
            if viewModel.medications.isEmpty {
                Text(L10n.text("medications.empty"))
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.medications.prefix(2)) { medication in
                    MedicationRow(medication: medication)
                }
            }
        }
        .cvCard()
    }

    private var appointmentPreview: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            HStack {
                Text(L10n.appointments)
                    .font(.headline)
                Spacer()
                NavigationLink(L10n.text("common.view_all"), destination: AppointmentListView())
                    .font(.caption.weight(.semibold))
            }
            if let appointment = viewModel.appointments.first {
                Label(DateFormatters.shortDateTime.string(from: appointment.appointmentAt), systemImage: "calendar.badge.clock")
                    .font(.body)
                    .foregroundColor(.primary)
            } else {
                Text(L10n.text("appointments.empty"))
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .cvCard()
    }
}
