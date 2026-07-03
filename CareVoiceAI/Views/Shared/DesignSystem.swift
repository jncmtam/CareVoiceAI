import SwiftUI

extension Color {
    static let careVoicePrimary = Color("CareVoicePrimary")
    static let riskNormal = Color("RiskNormal")
    static let riskAttention = Color("RiskAttention")
    static let riskIntervention = Color("RiskIntervention")
    static let appBackground = Color("AppBackground")
    static let appSurface = Color("Surface")
}

enum CVSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
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
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func cvCard() -> some View {
        modifier(CardBackground())
    }
}
