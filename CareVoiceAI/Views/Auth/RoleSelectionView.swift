import SwiftUI

struct RoleSelectionView: View {
    @EnvironmentObject private var session: SessionManager
    @State private var appeared = false

    var body: some View {
        NavigationView {
            ZStack {
                AuthDecorBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: CVSpacing.xl) {
                        AnimatedHeroHeader(
                            title: L10n.appName,
                            subtitle: L10n.text("role.subtitle"),
                            logoVariant: .brand
                        )
                        .padding(.top, CVSpacing.xl)

                        VStack(spacing: CVSpacing.lg) {
                            NavigationLink(destination: PatientLoginView()) {
                                RoleCard(
                                    title: L10n.rolePatient,
                                    subtitle: L10n.text("role.patient.subtitle"),
                                    logoVariant: .patient,
                                    stickers: ["mic.fill", "pills.fill", "calendar.badge.clock"]
                                )
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                HapticsManager.tap()
                                session.chooseRole(.patient)
                            })
                            .buttonStyle(RoleCardPressStyle())
                            .cvStaggeredAppear(index: 3, isVisible: appeared)

                            NavigationLink(destination: StaffLoginView()) {
                                RoleCard(
                                    title: L10n.roleStaff,
                                    subtitle: L10n.text("role.staff.subtitle"),
                                    logoVariant: .staff,
                                    stickers: ["list.bullet.clipboard.fill", "doc.text.viewfinder", "bell.badge.fill"]
                                )
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                HapticsManager.tap()
                                session.chooseRole(.nurse)
                            })
                            .buttonStyle(RoleCardPressStyle())
                            .cvStaggeredAppear(index: 4, isVisible: appeared)
                        }

                        HStack(spacing: CVSpacing.md) {
                            QuickActionSticker(title: L10n.text("role.hint.voice"), systemImage: "waveform")
                            QuickActionSticker(title: L10n.text("role.hint.care"), systemImage: "heart.fill", tint: .riskAttention)
                        }
                        .cvStaggeredAppear(index: 5, isVisible: appeared)

                        NavigationLink(destination: BackendSetupView()) {
                            Label(L10n.text("settings.connection"), systemImage: "network")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.careVoicePrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(CVSpacing.md)
                                .cvGlossyCard()
                        }
                        .cvStaggeredAppear(index: 6, isVisible: appeared)

                        Spacer(minLength: CVSpacing.xl)
                    }
                    .padding(CVSpacing.lg)
                }
                .cvDismissKeyboardOnScroll()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            appeared = true
        }
    }
}

private struct RoleCard: View {
    let title: String
    let subtitle: String
    let logoVariant: CareVoiceLogoVariant
    let stickers: [String]

    var body: some View {
        HStack(spacing: CVSpacing.lg) {
            CareVoiceLogo(variant: logoVariant, size: 64, showPulse: false)
            VStack(alignment: .leading, spacing: CVSpacing.sm) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: CVSpacing.xs) {
                    ForEach(stickers, id: \.self) { sticker in
                        StickerIcon(systemImage: sticker, size: 26, iconSize: 11)
                    }
                }
                .padding(.top, CVSpacing.xs)
            }
            Spacer()
            Image(systemName: "chevron.right.circle.fill")
                .font(.title3)
                .foregroundColor(.careVoicePrimary.opacity(0.55))
        }
        .cvGlossyCard(elevation: .hero)
        .accessibilityElement(children: .combine)
    }
}