import SwiftUI

enum CVButtonKind {
    case primary
    case secondary
    case destructive
}

struct CVButtonStyle: ButtonStyle {
    let kind: CVButtonKind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, CVSpacing.lg)
            .foregroundColor(foreground)
            .background(background(configuration: configuration))
            .cornerRadius(CVCornerRadius.md)
            .shadow(
                color: shadowColor(configuration: configuration),
                radius: configuration.isPressed ? 4 : 8,
                x: 0,
                y: configuration.isPressed ? 2 : 5
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1) : 0.62)
            .accessibilityAddTraits(.isButton)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .destructive:
            return .white
        case .secondary:
            return .careVoicePrimary
        }
    }

    @ViewBuilder
    private func background(configuration: Configuration) -> some View {
        switch kind {
        case .primary:
            LinearGradient(
                colors: configuration.isPressed
                    ? [Color.careVoicePrimaryGradientBottom, Color.careVoicePrimaryGradientTop]
                    : [Color.careVoicePrimaryGradientTop, Color.careVoicePrimaryGradientBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            ZStack {
                Color.careVoicePrimary.opacity(configuration.isPressed ? 0.16 : 0.10)
                RoundedRectangle(cornerRadius: CVCornerRadius.md)
                    .stroke(Color.careVoicePrimary.opacity(0.22), lineWidth: 1)
            }
        case .destructive:
            LinearGradient(
                colors: [
                    Color.riskIntervention.opacity(configuration.isPressed ? 0.78 : 1),
                    Color.riskIntervention.opacity(configuration.isPressed ? 0.68 : 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func shadowColor(configuration: Configuration) -> Color {
        switch kind {
        case .primary:
            return Color.careVoicePrimary.opacity(configuration.isPressed ? 0.18 : 0.28)
        case .secondary:
            return .clear
        case .destructive:
            return Color.riskIntervention.opacity(0.24)
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard !isLoading else { return }
            HapticsManager.tap()
            action()
        }) {
            HStack(spacing: CVSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(CVButtonStyle(kind: .primary))
        .disabled(isDisabled || isLoading)
        .accessibilityLabel(title)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticsManager.tap()
            action()
        }) {
            HStack(spacing: CVSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                }
                Text(title)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(CVButtonStyle(kind: .secondary))
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

struct DestructiveButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard !isLoading else { return }
            HapticsManager.warning()
            action()
        }) {
            HStack(spacing: CVSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
        }
        .buttonStyle(CVButtonStyle(kind: .destructive))
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}