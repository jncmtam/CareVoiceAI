import SwiftUI

extension Color {
    static let careVoicePrimary = Color("CareVoicePrimary")
    static let riskNormal = Color("RiskNormal")
    static let riskAttention = Color("RiskAttention")
    static let riskIntervention = Color("RiskIntervention")
    static let appBackground = Color("AppBackground")
    static let appSurface = Color("Surface")

    static var careVoicePrimaryGradientTop: Color {
        careVoicePrimary.opacity(0.92)
    }

    static var careVoicePrimaryGradientBottom: Color {
        careVoicePrimary.opacity(0.72)
    }
}

enum CVSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum CVCornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let sticker: CGFloat = 10
}

enum CVAnimation {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let springBouncy = Animation.spring(response: 0.55, dampingFraction: 0.68)
    static let easeOut = Animation.easeOut(duration: 0.22)
    static let staggerStep: Double = 0.08
}

enum CVFont {
    static let patientTitle = Font.system(.largeTitle, design: .default).weight(.bold)
    static let patientBody = Font.system(.title3, design: .default)
    static let patientAction = Font.system(.title3, design: .default).weight(.semibold)
    static let staffTitle = Font.system(.title2, design: .default).weight(.bold)
    static let staffBody = Font.system(.body, design: .default)
    static let caption = Font.system(.caption, design: .default)
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(CVSpacing.lg)
            .background(Color.appSurface)
            .cornerRadius(CVCornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CVCornerRadius.sm)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

enum CVCardElevation {
    case flat
    case raised
    case hero
}

struct GlossyCardBackground: ViewModifier {
    var elevation: CVCardElevation = .raised
    var tint: Color = .careVoicePrimary

    func body(content: Content) -> some View {
        content
            .padding(CVSpacing.lg)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.appSurface)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.02),
                                    tint.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                tint.opacity(0.12),
                                Color.primary.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var cornerRadius: CGFloat {
        switch elevation {
        case .flat: CVCornerRadius.sm
        case .raised: CVCornerRadius.md
        case .hero: CVCornerRadius.lg
        }
    }

    private var shadowColor: Color {
        switch elevation {
        case .flat: .clear
        case .raised: tint.opacity(0.12)
        case .hero: tint.opacity(0.2)
        }
    }

    private var shadowRadius: CGFloat {
        switch elevation {
        case .flat: 0
        case .raised: 10
        case .hero: 18
        }
    }

    private var shadowY: CGFloat {
        switch elevation {
        case .flat: 0
        case .raised: 5
        case .hero: 10
        }
    }
}

struct StaggeredAppearModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

struct AuthDecorBackground: View {
    var body: some View {
        ZStack {
            Color.appBackground
            LinearGradient(
                colors: [
                    Color.careVoicePrimary.opacity(0.14),
                    Color.appBackground,
                    Color.careVoicePrimary.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.careVoicePrimary.opacity(0.1))
                .frame(width: 220, height: 220)
                .blur(radius: 2)
                .offset(x: -100, y: -250)
            Circle()
                .fill(Color.careVoicePrimary.opacity(0.08))
                .frame(width: 160, height: 160)
                .offset(x: 120, y: -190)
            Circle()
                .fill(Color.careVoicePrimary.opacity(0.06))
                .frame(width: 280, height: 280)
                .offset(x: 30, y: 310)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func cvCard() -> some View {
        modifier(CardBackground())
    }

    func cvGlossyCard(elevation: CVCardElevation = .raised, tint: Color = .careVoicePrimary) -> some View {
        modifier(GlossyCardBackground(elevation: elevation, tint: tint))
    }

    func cvStaggeredAppear(index: Int, isVisible: Bool) -> some View {
        modifier(StaggeredAppearModifier())
    }

    func cvDismissKeyboardOnScroll() -> some View {
        modifier(KeyboardDismissOnScrollModifier())
    }

    func cvKeyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.text("common.done")) {
                    KeyboardDismissal.endEditing()
                }
            }
        }
    }
}

private struct KeyboardDismissOnScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollDismissesKeyboard(.interactively)
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { _ in KeyboardDismissal.endEditing() }
            )
        }
    }
}