import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var notifications: NotificationManager
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        List {
            Section(header: Text(L10n.text("settings.account"))) {
                HStack(spacing: CVSpacing.md) {
                    CareVoiceLogo(
                        variant: CareVoiceLogoVariant.forRole(session.currentRole),
                        size: 48,
                        showPulse: false
                    )
                    VStack(alignment: .leading, spacing: CVSpacing.xs) {
                        Text(L10n.appName)
                            .font(.headline)
                        Text(L10n.text("settings.app_tagline"))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, CVSpacing.xs)

                if let user = session.currentUser {
                    Label(user.fullName, systemImage: "person.crop.circle")
                    Label(L10n.text("role.\(user.role.rawValue)"), systemImage: "person.text.rectangle")
                }
            }

            Section(header: Text(L10n.notifications)) {
                Button(action: { Task { await viewModel.requestNotifications() } }) {
                    Label(L10n.text("settings.enable_notifications"), systemImage: "bell.badge.fill")
                }
                Toggle(L10n.text("settings.checkin_reminders"), isOn: $viewModel.preferences.checkinRemindersEnabled)
                Toggle(L10n.text("settings.medication_reminders"), isOn: $viewModel.preferences.medicationRemindersEnabled)
                Toggle(L10n.text("settings.appointment_reminders"), isOn: $viewModel.preferences.appointmentRemindersEnabled)
                if session.currentRole == .nurse || session.currentRole == .doctor {
                    Toggle(L10n.text("settings.critical_alerts"), isOn: $viewModel.preferences.criticalStaffAlertsEnabled)
                }
                PrimaryButton(
                    title: L10n.save,
                    systemImage: "checkmark.circle.fill",
                    isLoading: viewModel.isSaving
                ) {
                    Task {
                        let isStaff = session.currentRole == .nurse || session.currentRole == .doctor
                        await viewModel.savePreferences(isStaff: isStaff)
                    }
                }
                if let success = viewModel.saveSuccessMessage {
                    HStack(spacing: CVSpacing.md) {
                        StickerIcon(systemImage: "checkmark.seal.fill", size: 40, iconSize: 18, tint: .riskNormal)
                        VStack(alignment: .leading, spacing: CVSpacing.xs) {
                            Text(L10n.text("settings.notifications_saved"))
                                .font(.subheadline.weight(.semibold))
                            Text(success)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, CVSpacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Section(header: Text(L10n.text("settings.demo"))) {
                Toggle(L10n.text("settings.demo_mode"), isOn: $viewModel.isDemoMode)
                    .onChange(of: viewModel.isDemoMode) { enabled in
                        viewModel.updateDemoMode(enabled)
                    }

                if viewModel.isDemoMode {
                    Label(L10n.text("settings.demo_mode_on_hint"), systemImage: "iphone")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    NavigationLink(destination: BackendSetupView()) {
                        Label(L10n.text("settings.connection"), systemImage: "network")
                    }
                }
            }

            if let error = viewModel.error {
                Section {
                    ErrorBannerView(message: error.userMessage)
                }
            }

            Section {
                Button(role: .destructive, action: { Task { await viewModel.logout() } }) {
                    Label(L10n.logout, systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button(role: .destructive, action: { Task { await viewModel.changeRole() } }) {
                    Label(L10n.changeRole, systemImage: "person.2.fill")
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .cvDismissKeyboardOnScroll()
        .navigationTitle(L10n.settings)
        .task {
            await viewModel.loadPreferences()
            await notifications.refreshAuthorizationStatus()
        }
    }
}
