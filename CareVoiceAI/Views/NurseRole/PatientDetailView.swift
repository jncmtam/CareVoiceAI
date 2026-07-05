import SwiftUI

struct PatientDetailView: View {
    @StateObject private var viewModel: PatientDetailViewModel

    init(patientId: String) {
        _viewModel = StateObject(wrappedValue: PatientDetailViewModel(patientId: patientId))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CVSpacing.lg) {
                if let error = viewModel.error {
                    ErrorBannerView(message: error.userMessage) {
                        Task { await viewModel.load() }
                    }
                }

                if let profile = viewModel.profile {
                    profileHeader(profile)
                }

                prescriptionUploadSection
                medicationsSection
                appointmentsSection

                if let header = viewModel.timelineHeader, header.caregiverAlertSentAt != nil {
                    caregiverAlertBanner(sentAt: header.caregiverAlertSentAt!)
                }

                if viewModel.isLoading && viewModel.timeline.isEmpty {
                    LoadingView(title: L10n.loading)
                        .frame(height: 240)
                } else if viewModel.timeline.isEmpty {
                    EmptyStateView(title: L10n.text("timeline.empty"), systemImage: "clock.badge.questionmark")
                        .frame(height: 260)
                } else {
                    ForEach(viewModel.timeline) { entry in
                        TimelineEntryRow(
                            entry: entry,
                            patientPhone: viewModel.profile?.phoneNumber,
                            caregiverPhone: viewModel.profile?.caregiverPhoneNumber,
                            onViewed: { Task { await viewModel.markViewed(entry) } },
                            onCalledBack: { Task { await viewModel.markCalledBack(entry) } },
                            onResolved: { Task { await viewModel.markResolved(entry) } },
                            onNote: { viewModel.beginNoteEditing(for: entry) }
                        )
                    }
                }
            }
            .padding(CVSpacing.lg)
        }
        .cvDismissKeyboardOnScroll()
        .background(Color.appBackground)
        .navigationTitle(viewModel.profile?.fullName ?? L10n.text("patient.detail"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: CVSpacing.sm) {
                    NavigationLink(destination: DocumentUploadView(patientId: viewModel.patientId)) {
                        Image(systemName: "doc.badge.plus")
                    }
                    Button(L10n.text("staff.edit_patient")) {
                        viewModel.beginProfileEditing()
                    }
                    .disabled(viewModel.profile == nil)
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .patientDataUpdated)) { notification in
            guard let updatedId = notification.object as? String, updatedId == viewModel.patientId else { return }
            Task { await viewModel.load() }
        }
        .sheet(isPresented: $viewModel.isEditingProfile) {
            EditPatientSheet(
                fullName: $viewModel.editFullName,
                caregiverName: $viewModel.editCaregiverName,
                phone: $viewModel.editPhone,
                caregiverPhone: $viewModel.editCaregiverPhone,
                notes: $viewModel.editNotes,
                isSaving: viewModel.isSavingProfile,
                onSave: { Task { await viewModel.saveProfile() } }
            )
        }
        .sheet(item: $viewModel.editingEntry) { _ in
            NoteEditorSheet(
                title: L10n.addNote,
                note: $viewModel.noteText,
                onSave: { Task { await viewModel.saveNote() } }
            )
        }
    }

    private var prescriptionUploadSection: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.text("staff.upload_prescription_card"),
                systemImage: "doc.text.viewfinder",
                subtitle: L10n.text("staff.upload_prescription_hint"),
                tint: .careVoicePrimary
            )
            NavigationLink(destination: DocumentUploadView(patientId: viewModel.patientId)) {
                Label(L10n.uploadDocument, systemImage: "icloud.and.arrow.up.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(CVButtonStyle(kind: .primary))
        }
        .cvGlossyCard(elevation: .raised)
    }

    private var medicationsSection: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(title: L10n.medications, systemImage: "pills.fill", tint: .riskNormal)
            if viewModel.medications.isEmpty {
                Text(L10n.text("medications.empty"))
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.medications) { medication in
                    MedicationRow(medication: medication)
                    if medication.id != viewModel.medications.last?.id {
                        Divider()
                    }
                }
            }
        }
        .cvGlossyCard()
    }

    private var appointmentsSection: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(title: L10n.appointments, systemImage: "calendar.badge.clock", tint: .riskAttention)
            if viewModel.appointments.isEmpty {
                Text(L10n.text("appointments.empty"))
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.appointments) { appointment in
                    VStack(alignment: .leading, spacing: CVSpacing.xs) {
                        Label(
                            DateFormatters.shortDateTime.string(from: appointment.appointmentAt),
                            systemImage: "clock.fill"
                        )
                        .font(CVFont.patientAction)
                        if let department = appointment.department {
                            Text(department)
                                .font(.body)
                        }
                        if let doctorName = appointment.doctorName {
                            Text(doctorName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if appointment.id != viewModel.appointments.last?.id {
                        Divider()
                    }
                }
            }
        }
        .cvGlossyCard()
    }

    private func caregiverAlertBanner(sentAt: Date) -> some View {
        HStack(spacing: CVSpacing.md) {
            StickerIcon(systemImage: "message.fill", size: 36, iconSize: 16, tint: .riskAttention)
            VStack(alignment: .leading, spacing: CVSpacing.xs) {
                Text(L10n.text("staff.caregiver_alert_banner"))
                    .font(.subheadline.weight(.semibold))
                Text(DateFormatters.shortDateTime.string(from: sentAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .cvGlossyCard(elevation: .raised)
    }

    private func profileHeader(_ profile: PatientProfile) -> some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(profile.fullName)
                        .font(CVFont.staffTitle)
                    Text(profile.patientCode)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                RiskBadge(level: profile.latestRiskLevel)
            }
            if let header = viewModel.timelineHeader {
                if let missed = header.missedMedicationDoses, missed > 0 {
                    Label(
                        String(format: L10n.text("staff.patient.missed_doses"), missed),
                        systemImage: "pills.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.riskAttention)
                }
                if let reasons = header.alertReasons, !reasons.isEmpty {
                    VStack(alignment: .leading, spacing: CVSpacing.xs) {
                        Text(L10n.text("staff.patient.alert_reasons"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        ForEach(reasons.prefix(3), id: \.self) { reason in
                            Label(reason, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            if let diagnoses = profile.diagnoses, !diagnoses.isEmpty {
                Text(diagnoses.joined(separator: ", "))
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            if let phone = profile.phoneNumber {
                PhoneCallChip(title: L10n.text("staff.call_patient"), phoneNumber: phone)
            }
            if let caregiverPhone = profile.caregiverPhoneNumber {
                PhoneCallChip(
                    title: L10n.text("staff.call_caregiver"),
                    phoneNumber: caregiverPhone,
                    systemImage: "phone.badge.waveform.fill",
                    tint: .riskAttention
                )
            }
            if let caregiver = profile.caregiverName {
                Label(caregiver, systemImage: "person.2.fill")
                    .font(.body)
            }
            if let saved = viewModel.profileSavedMessage {
                Label(saved, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
        }
        .cvGlossyCard(elevation: .raised)
    }
}

private struct EditPatientSheet: View {
    @Binding var fullName: String
    @Binding var caregiverName: String
    @Binding var phone: String
    @Binding var caregiverPhone: String
    @Binding var notes: String
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: CVSpacing.lg) {
                    FormField(title: L10n.text("patient.full_name"), text: $fullName, systemImage: "person.fill")
                    FormField(title: L10n.text("patient.caregiver_name"), text: $caregiverName, systemImage: "person.2.fill")
                    FormField(
                        title: L10n.phoneNumber,
                        text: $phone,
                        systemImage: "phone.fill",
                        hint: L10n.text("validation.phone.hint"),
                        keyboardType: .phonePad
                    )
                    FormField(
                        title: L10n.text("patient.caregiver_phone"),
                        text: $caregiverPhone,
                        systemImage: "phone.badge.waveform.fill",
                        hint: L10n.text("validation.phone.optional_hint"),
                        keyboardType: .phonePad
                    )
                    VStack(alignment: .leading, spacing: CVSpacing.sm) {
                        Text(L10n.text("patient.notes"))
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $notes)
                            .frame(minHeight: 140)
                            .padding(CVSpacing.sm)
                            .background(Color.appSurface)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                    }
                    PrimaryButton(
                        title: L10n.save,
                        systemImage: "checkmark.circle.fill",
                        isLoading: isSaving
                    ) {
                        onSave()
                    }
                }
                .padding(CVSpacing.lg)
            }
            .cvDismissKeyboardOnScroll()
            .background(Color.appBackground)
            .navigationTitle(L10n.text("staff.edit_patient"))
            .navigationBarTitleDisplayMode(.inline)
            .cvKeyboardDoneToolbar()
        }
        .navigationViewStyle(.stack)
    }
}

private struct NoteEditorSheet: View {
    let title: String
    @Binding var note: String
    let onSave: () -> Void
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: CVSpacing.lg) {
                Text(L10n.text("staff.timeline.note_hint"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $note)
                    .padding(CVSpacing.sm)
                    .background(Color.appSurface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))
                    .frame(minHeight: 220)
                PrimaryButton(title: L10n.save, systemImage: "checkmark.circle.fill") {
                    onSave()
                    presentationMode.wrappedValue.dismiss()
                }
                Spacer()
            }
            .padding(CVSpacing.lg)
            .background(Color.appBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}
