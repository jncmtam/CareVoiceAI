import SwiftUI

struct RoleSelectionView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: CVSpacing.xl) {
                    VStack(alignment: .leading, spacing: CVSpacing.sm) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.careVoicePrimary)
                        Text(L10n.appName)
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(.primary)
                        Text(L10n.text("role.subtitle"))
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, CVSpacing.xl)

                    NavigationLink(destination: PatientLoginView()) {
                        RoleCard(
                            title: L10n.rolePatient,
                            subtitle: L10n.text("role.patient.subtitle"),
                            systemImage: "person.crop.circle.badge.checkmark"
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        session.chooseRole(.patient)
                    })
                    .buttonStyle(PlainButtonStyle())

                    NavigationLink(destination: StaffLoginView()) {
                        RoleCard(
                            title: L10n.roleStaff,
                            subtitle: L10n.text("role.staff.subtitle"),
                            systemImage: "stethoscope"
                        )
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        session.chooseRole(.nurse)
                    })
                    .buttonStyle(PlainButtonStyle())

                    Spacer(minLength: CVSpacing.xl)
                }
                .padding(CVSpacing.lg)
            }
            .background(Color.appBackground)
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

private struct RoleCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: CVSpacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.careVoicePrimary)
                .frame(width: 56, height: 56)
                .background(Color.careVoicePrimary.opacity(0.12))
                .cornerRadius(8)
            VStack(alignment: .leading, spacing: CVSpacing.xs) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .cvCard()
        .accessibilityElement(children: .combine)
    }
}
