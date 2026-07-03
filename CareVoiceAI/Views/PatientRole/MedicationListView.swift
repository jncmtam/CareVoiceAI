import SwiftUI

struct MedicationListView: View {
    @StateObject private var viewModel = MedicationListViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.medications.isEmpty {
                LoadingView(title: L10n.loading)
            } else if let error = viewModel.error, viewModel.medications.isEmpty {
                ErrorBannerView(message: error.userMessage) {
                    Task { await viewModel.load() }
                }
                .padding(CVSpacing.lg)
            } else if viewModel.medications.isEmpty {
                EmptyStateView(title: L10n.text("medications.empty"), systemImage: "pills")
            } else {
                List(viewModel.medications) { medication in
                    MedicationRow(medication: medication) {
                        scheduleReminder(for: medication)
                    }
                        .padding(.vertical, CVSpacing.sm)
                }
                .listStyle(PlainListStyle())
                .refreshable { await viewModel.load() }
            }
        }
        .navigationTitle(L10n.medications)
        .task { await viewModel.load() }
    }

    private func scheduleReminder(for medication: Medication) {
        Task { @MainActor in
            _ = await NotificationManager.shared.requestPermissionAtValueMoment()
            let times = medication.timesOfDay?.isEmpty == false ? medication.timesOfDay! : [.morning]
            for time in times {
                var components = DateComponents()
                components.hour = time.defaultHour
                components.minute = 0
                NotificationManager.shared.scheduleMedicationReminder(
                    id: "\(medication.id ?? medication.name)-\(time.rawValue)",
                    title: "\(medication.name) \(medication.dosage ?? "")",
                    dateComponents: components
                )
            }
            HapticsManager.success()
        }
    }
}

struct MedicationRow: View {
    let medication: Medication
    var onReminder: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.sm) {
            Text(medication.name)
                .font(CVFont.patientAction)
                .foregroundColor(.primary)
            if let dosage = medication.dosage {
                Label(dosage, systemImage: "pills.fill")
                    .font(CVFont.patientBody)
            }
            if let frequency = medication.frequency {
                Label(frequency, systemImage: "clock.fill")
                    .font(.body)
            }
            if let instructions = medication.instructions {
                Text(instructions)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            if let onReminder {
                SecondaryButton(title: L10n.text("medications.remind_me"), systemImage: "bell.fill", action: onReminder)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension MedicationTimeOfDay {
    var defaultHour: Int {
        switch self {
        case .morning:
            return 8
        case .noon:
            return 12
        case .afternoon:
            return 15
        case .evening:
            return 19
        case .bedtime:
            return 21
        }
    }
}
