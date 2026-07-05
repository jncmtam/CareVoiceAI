import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        Group {
            if session.isRestoring {
                LoadingView(title: L10n.loadingOpeningApp, logoVariant: .brand)
            } else if session.isAuthenticated {
                switch session.currentRole {
                case .patient, .caregiver:
                    PatientRootView()
                case .nurse, .doctor, .admin:
                    StaffRootView()
                case .none:
                    RoleSelectionView()
                }
            } else {
                RoleSelectionView()
            }
        }
        .accentColor(.careVoicePrimary)
    }
}
