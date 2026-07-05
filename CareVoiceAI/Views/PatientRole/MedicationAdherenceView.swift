import SwiftUI

struct MedicationAdherenceView: View {
    let medication: Medication
    let slot: MedicationTimeOfDay

    @StateObject private var viewModel: MedicationAdherenceViewModel
    @Environment(\.presentationMode) private var presentationMode

    init(medication: Medication, slot: MedicationTimeOfDay) {
        self.medication = medication
        self.slot = slot
        _viewModel = StateObject(wrappedValue: MedicationAdherenceViewModel(medication: medication, slot: slot))
    }

    var body: some View {
        VStack(spacing: CVSpacing.xl) {
            StickerIcon(systemImage: "pills.fill", size: 64, iconSize: 28, tint: .careVoicePrimary)
            Text(medication.name)
                .font(CVFont.patientTitle)
                .multilineTextAlignment(.center)
            Text(viewModel.prompt)
                .font(CVFont.patientBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let message = viewModel.successMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
            }
            if let error = viewModel.error {
                ErrorBannerView(message: error.userMessage)
            }

            HStack(spacing: CVSpacing.md) {
                PrimaryButton(
                    title: L10n.text("adherence.taken_yes"),
                    systemImage: "checkmark.circle.fill",
                    isLoading: viewModel.isSubmitting,
                    isDisabled: viewModel.didRecord
                ) {
                    Task { await viewModel.record(taken: true) }
                }
                SecondaryButton(
                    title: L10n.text("adherence.taken_no"),
                    systemImage: "xmark.circle.fill",
                    isDisabled: viewModel.isSubmitting || viewModel.didRecord
                ) {
                    Task { await viewModel.record(taken: false) }
                }
            }
        }
        .padding(CVSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .navigationTitle(L10n.text("adherence.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.restoreIfAlreadyRecorded()
            if !viewModel.didRecord {
                SpeechReminderService.shared.speak(viewModel.prompt)
            }
        }
        .onChange(of: viewModel.didRecord) { didRecord in
            guard didRecord else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

@MainActor
final class MedicationAdherenceViewModel: ObservableObject {
    @Published var isSubmitting = false
    @Published var didRecord = false
    @Published var successMessage: String?
    @Published var error: APIError?

    let prompt: String
    private let medicationId: String
    private let slot: String
    private let apiClient: APIClient

    init(medication: Medication, slot: MedicationTimeOfDay, apiClient: APIClient = .shared) {
        self.medicationId = medication.id ?? medication.name
        self.slot = slot.rawValue
        self.apiClient = apiClient
        self.prompt = SpeechReminderService.shared.medicationPrompt(name: medication.name, dosage: medication.dosage)
    }

    func restoreIfAlreadyRecorded() {
        guard MedicationAdherenceTracker.shared.isRecorded(medicationId: medicationId, slot: slot) else { return }
        didRecord = true
        successMessage = L10n.text("adherence.already_recorded")
    }

    func record(taken: Bool) async {
        guard !didRecord else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            let response = try await apiClient.recordMedicationAdherence(
                medicationId: medicationId,
                slot: slot,
                taken: taken
            )
            didRecord = true
            successMessage = response.message
            MedicationAdherenceTracker.shared.markRecorded(medicationId: medicationId, slot: slot)
            MorningRoutineTracker.shared.markMedicationDone()
            HapticsManager.success()
        } catch {
            self.error = error as? APIError ?? .unknown(message: error.localizedDescription)
        }
    }
}