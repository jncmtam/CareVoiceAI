import SwiftUI

struct PatientRootView: View {
    @ObservedObject private var navigation = PatientNavigationCoordinator.shared

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationView {
                PatientHomeView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.patientHomeTitle, systemImage: "house.fill") }
            .tag(0)

            NavigationView {
                CheckinHistoryView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.history, systemImage: "clock.fill") }
            .tag(1)

            NavigationView {
                MedicationListView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.medications, systemImage: "pills.fill") }
            .tag(2)

            NavigationView {
                HotlineView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.hotline, systemImage: "mic.circle.fill") }
            .tag(3)

            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.settings, systemImage: "gearshape.fill") }
            .tag(4)
        }
    }
}