import SwiftUI

enum CareVoiceLogoVariant {
    case brand
    case patient
    case staff

    var assetName: String {
        switch self {
        case .brand:
            return "CareVoiceLogoBrand"
        case .patient:
            return "CareVoiceLogoPatient"
        case .staff:
            return "CareVoiceLogoStaff"
        }
    }

    static func forRole(_ role: UserRole?) -> CareVoiceLogoVariant {
        switch role {
        case .patient, .caregiver:
            return .patient
        case .nurse, .doctor, .admin:
            return .staff
        case .none:
            return .brand
        }
    }
}

struct CareVoiceLogo: View {
    let variant: CareVoiceLogoVariant
    var size: CGFloat = 64
    var showPulse: Bool = false
    var cornerRadius: CGFloat?

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? size * 0.22
    }

    var body: some View {
        ZStack {
            if showPulse {
                Circle()
                    .fill(Color.careVoicePrimary.opacity(pulse ? 0.18 : 0.08))
                    .frame(width: size * 1.28, height: size * 1.28)
                    .scaleEffect(pulse ? 1.08 : 0.94)
            }

            Image(variant.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: max(1, size * 0.02))
                )
                .shadow(color: Color.careVoicePrimary.opacity(0.24), radius: size * 0.1, x: 0, y: size * 0.05)
        }
        .accessibilityLabel(L10n.appName)
        .onAppear {
            guard showPulse, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct CareVoiceLogoBadge: View {
    let variant: CareVoiceLogoVariant
    var size: CGFloat = 28

    var body: some View {
        CareVoiceLogo(variant: variant, size: size, showPulse: false, cornerRadius: size * 0.24)
    }
}