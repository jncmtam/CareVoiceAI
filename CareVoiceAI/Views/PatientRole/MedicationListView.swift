import SwiftUI

private struct MedicationAdherenceTarget: Hashable {
    let medication: Medication
    let slot: MedicationTimeOfDay

    var id: String {
        "\(medication.id ?? medication.name)-\(slot.rawValue)"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct MedicationListView: View {
    @StateObject private var viewModel = MedicationListViewModel()
    @ObservedObject private var adherenceTracker = MedicationAdherenceTracker.shared
    @ObservedObject private var navigation = PatientNavigationCoordinator.shared
    @State private var adherenceTarget: MedicationAdherenceTarget?

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
                ScrollView {
                    LazyVStack(spacing: CVSpacing.lg) {
                        ForEach(viewModel.medications) { medication in
                            medicationSection(for: medication)
                        }
                    }
                    .padding(CVSpacing.lg)
                }
                .cvDismissKeyboardOnScroll()
                .refreshable { await viewModel.load() }
                .background(adherenceNavigationLink)
            }
        }
        .navigationTitle(L10n.medications)
        .task {
            await viewModel.load()
            await viewModel.scheduleRemindersIfNeeded()
            openPendingAdherenceTargetIfNeeded()
        }
        .onChange(of: navigation.pendingMedicationId) { _ in
            openPendingAdherenceTargetIfNeeded()
        }
    }

    @ViewBuilder
    private var adherenceNavigationLink: some View {
        NavigationLink(
            isActive: Binding(
                get: { adherenceTarget != nil },
                set: { isActive in
                    if !isActive {
                        adherenceTarget = nil
                    }
                }
            )
        ) {
            if let target = adherenceTarget {
                MedicationAdherenceView(medication: target.medication, slot: target.slot)
                    .id(target.id)
            } else {
                EmptyView()
            }
        } label: {
            EmptyView()
        }
        .hidden()
    }

    @ViewBuilder
    private func medicationSection(for medication: Medication) -> some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            MedicationRow(medication: medication)

            let slots = medication.timesOfDay?.isEmpty == false ? medication.timesOfDay! : [.morning]
            ForEach(slots, id: \.self) { slot in
                slotRow(for: medication, slot: slot)
            }
        }
        .cvCard()
    }

    private func openPendingAdherenceTargetIfNeeded() {
        guard let pending = navigation.consumePendingMedicationTarget(),
              let slot = MedicationTimeOfDay(rawValue: pending.slot),
              let medication = viewModel.medications.first(where: { ($0.id ?? $0.name) == pending.medicationId })
        else { return }
        adherenceTarget = MedicationAdherenceTarget(medication: medication, slot: slot)
    }

    @ViewBuilder
    private func slotRow(for medication: Medication, slot: MedicationTimeOfDay) -> some View {
        let medicationId = medication.id ?? medication.name
        let isRecorded = adherenceTracker.isRecorded(medicationId: medicationId, slot: slot.rawValue)

        if isRecorded {
            HStack(spacing: CVSpacing.sm) {
                Label(
                    String(format: L10n.text("adherence.slot_done"), slot.displayName),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.green)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, CVSpacing.md)
            .background(Color.green.opacity(0.08))
            .cornerRadius(CVCornerRadius.sm)
            .accessibilityAddTraits(.isStaticText)
        } else {
            Button {
                adherenceTarget = MedicationAdherenceTarget(medication: medication, slot: slot)
            } label: {
                HStack(spacing: CVSpacing.sm) {
                    Label(
                        String(format: L10n.text("adherence.confirm_slot"), slot.displayName),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.careVoicePrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, CVSpacing.md)
                .background(Color.careVoicePrimary.opacity(0.08))
                .cornerRadius(CVCornerRadius.sm)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

struct MedicationRow: View {
    let medication: Medication

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
        }
        .accessibilityElement(children: .combine)
    }
}

extension MedicationTimeOfDay {
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

    var displayName: String {
        switch self {
        case .morning:
            return L10n.text("medication.slot.morning")
        case .noon:
            return L10n.text("medication.slot.noon")
        case .afternoon:
            return L10n.text("medication.slot.afternoon")
        case .evening:
            return L10n.text("medication.slot.evening")
        case .bedtime:
            return L10n.text("medication.slot.bedtime")
        }
    }
}
