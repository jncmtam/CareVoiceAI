import SwiftUI

struct PatientDetailView: View {
    @StateObject private var viewModel: PatientDetailViewModel
    @State private var noteAction: HandlingStatus = .viewed

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
                            onViewed: { Task { await viewModel.markViewed(entry) } },
                            onCallback: {
                                noteAction = .calledBack
                                viewModel.editingEntry = entry
                                viewModel.noteText = ""
                            },
                            onNote: {
                                noteAction = .viewed
                                viewModel.editingEntry = entry
                                viewModel.noteText = ""
                            }
                        )
                    }
                }
            }
            .padding(CVSpacing.lg)
        }
        .background(Color.appBackground)
        .navigationTitle(viewModel.profile?.fullName ?? L10n.text("patient.detail"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(item: $viewModel.editingEntry) { entry in
            NoteEditorSheet(
                title: noteAction == .calledBack ? L10n.callBack : L10n.addNote,
                note: $viewModel.noteText,
                onSave: {
                    Task {
                        if noteAction == .calledBack {
                            await viewModel.markCalledBack(entry)
                        } else {
                            await viewModel.saveNote()
                        }
                    }
                }
            )
        }
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
            if let diagnoses = profile.diagnoses, !diagnoses.isEmpty {
                Text(diagnoses.joined(separator: ", "))
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            if let phone = profile.phoneNumber {
                Label(phone, systemImage: "phone.fill")
                    .font(.body)
            }
            if let caregiver = profile.caregiverName {
                Label(caregiver, systemImage: "person.2.fill")
                    .font(.body)
            }
        }
        .cvCard()
    }
}

private struct NoteEditorSheet: View {
    let title: String
    @Binding var note: String
    let onSave: () -> Void
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            VStack(spacing: CVSpacing.lg) {
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
