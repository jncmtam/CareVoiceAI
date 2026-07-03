import SwiftUI

struct StaffRootView: View {
    var body: some View {
        TabView {
            NavigationView {
                StaffDashboardView()
            }
            .navigationViewStyle(.stack)
            .tabItem { Label(L10n.staffDashboard, systemImage: "list.bullet.rectangle.fill") }

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
