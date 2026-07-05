import SwiftUI

struct AppointmentListView: View {
    @StateObject private var viewModel = AppointmentListViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.appointments.isEmpty {
                LoadingView(title: L10n.loading)
            } else if let error = viewModel.error, viewModel.appointments.isEmpty {
                ErrorBannerView(message: error.userMessage) {
                    Task { await viewModel.load() }
                }
                .padding(CVSpacing.lg)
            } else if viewModel.appointments.isEmpty {
                EmptyStateView(title: L10n.text("appointments.empty"), systemImage: "calendar")
            } else {
                List(viewModel.appointments) { appointment in
                    VStack(alignment: .leading, spacing: CVSpacing.sm) {
                        Label(DateFormatters.shortDateTime.string(from: appointment.appointmentAt), systemImage: "calendar.badge.clock")
                            .font(CVFont.patientAction)
                        if let department = appointment.department {
                            Text(department)
                                .font(.body)
                        }
                        if let doctorName = appointment.doctorName {
                            Text(doctorName)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        if appointment.appointmentAt > Date() {
                            Label(
                                L10n.text("appointments.reminder_auto"),
                                systemImage: "bell.badge"
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, CVSpacing.sm)
                }
                .listStyle(PlainListStyle())
                .cvDismissKeyboardOnScroll()
                .refreshable { await viewModel.load() }
            }
        }
        .navigationTitle(L10n.appointments)
        .task {
            await viewModel.load()
            await viewModel.scheduleRemindersIfNeeded()
        }
    }
}
