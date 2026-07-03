import SwiftUI

struct PatientRootView: View {
    var body: some View {
        TabView {
            NavigationView {
                PatientHomeView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.patientHomeTitle, systemImage: "house.fill") }

            NavigationView {
                CheckinHistoryView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.history, systemImage: "clock.fill") }

            NavigationView {
                MedicationListView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.medications, systemImage: "pills.fill") }

            NavigationView {
                HotlineView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.hotline, systemImage: "mic.circle.fill") }

            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.settings, systemImage: "gearshape.fill") }
        }
    }
}
