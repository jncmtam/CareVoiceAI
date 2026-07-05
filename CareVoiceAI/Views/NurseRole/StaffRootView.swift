import SwiftUI

@available(iOS 16.0, *)
struct StaffRootView: View {
    @StateObject private var notificationsViewModel = StaffNotificationsViewModel()

    var body: some View {
        TabView {
            NavigationView {
                StaffDashboardView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.staffDashboard, systemImage: "list.bullet.rectangle.fill") }

            NavigationView {
                StaffNotificationsView(viewModel: notificationsViewModel)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label(L10n.text("staff.notifications.title_short"), systemImage: "bell.badge.fill")
            }
            .badge(notificationsViewModel.unreadCount)
            .task {
                await notificationsViewModel.load(notifyOnNew: true)
                notificationsViewModel.startAutoRefresh()
            }

            NavigationView {
                NewPatientView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.newPatient, systemImage: "person.badge.plus") }

            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.settings, systemImage: "gearshape.fill") }
        }
    }
}
