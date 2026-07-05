import SwiftUI

struct PatientHomeView: View {
    @StateObject private var viewModel = PatientHomeViewModel()
    @ObservedObject private var morningTracker = MorningRoutineTracker.shared
    @ObservedObject private var adherenceTracker = MedicationAdherenceTracker.shared
    @State private var appeared = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CVSpacing.lg) {
                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage) {
                        Task { await viewModel.load() }
                    }
                    .cvStaggeredAppear(index: 0, isVisible: appeared)
                }

                MorningProgressCard(tracker: morningTracker)
                    .cvStaggeredAppear(index: 1, isVisible: appeared)
                medicationPreview
                    .cvStaggeredAppear(index: 2, isVisible: appeared)
                appointmentPreview
                    .cvStaggeredAppear(index: 3, isVisible: appeared)

            }
            .padding(CVSpacing.lg)
        }
        .cvDismissKeyboardOnScroll()
        .background(Color.appBackground)
        .navigationTitle(L10n.patientHomeTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CareVoiceLogoBadge(variant: .patient, size: 30)
            }
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .onAppear {
            appeared = true
            if !morningTracker.isMorningComplete {
                SpeechReminderService.shared.speakMorningWelcome()
            }
        }
    }

    private var medicationPreview: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            HStack {
                SectionHeaderView(
                    title: L10n.medications,
                    systemImage: "pills.fill",
                    tint: .riskNormal
                )
                Spacer()
                NavigationLink {
                    MedicationListView()
                } label: {
                    QuickActionSticker(title: L10n.text("common.view_all"), systemImage: "arrow.right", tint: .careVoicePrimary)
                }
            }
            if viewModel.medications.isEmpty {
                HStack(spacing: CVSpacing.sm) {
                    StickerIcon(systemImage: "tray", size: 28, iconSize: 12, tint: .secondary)
                    Text(L10n.text("medications.empty"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(viewModel.medications.prefix(2)) { medication in
                    if let target = pendingSlot(for: medication) {
                        NavigationLink {
                            MedicationAdherenceView(medication: medication, slot: target)
                        } label: {
                            HStack {
                                MedicationRow(medication: medication)
                                Spacer()
                                Label(L10n.text("adherence.confirm_now"), systemImage: "checkmark.circle.fill")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.careVoicePrimary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        MedicationRow(medication: medication)
                    }
                }
            }
        }
        .cvGlossyCard()
    }

    private func pendingSlot(for medication: Medication) -> MedicationTimeOfDay? {
        let medicationId = medication.id ?? medication.name
        let slots = medication.timesOfDay?.isEmpty == false ? medication.timesOfDay! : [.morning]
        return slots.first { !adherenceTracker.isRecorded(medicationId: medicationId, slot: $0.rawValue) }
    }

    private var appointmentPreview: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            HStack {
                SectionHeaderView(
                    title: L10n.appointments,
                    systemImage: "calendar.badge.clock",
                    tint: .riskAttention
                )
                Spacer()
                NavigationLink {
                    AppointmentListView()
                } label: {
                    QuickActionSticker(title: L10n.text("common.view_all"), systemImage: "arrow.right", tint: .careVoicePrimary)
                }
            }
            if let appointment = viewModel.appointments.first {
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    HStack(spacing: CVSpacing.sm) {
                        StickerIcon(systemImage: "clock.fill", size: 28, iconSize: 12, tint: .riskAttention)
                        Text(DateFormatters.shortDateTime.string(from: appointment.appointmentAt))
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    if let department = appointment.department {
                        Text(department)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let doctorName = appointment.doctorName {
                        Text(doctorName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                HStack(spacing: CVSpacing.sm) {
                    StickerIcon(systemImage: "calendar.badge.exclamationmark", size: 28, iconSize: 12, tint: .secondary)
                    Text(L10n.text("appointments.empty"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .cvGlossyCard()
    }
}