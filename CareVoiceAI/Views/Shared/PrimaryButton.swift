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
            .cornerRadius(8)
            .opacity(isEnabled ? 1 : 0.62)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
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

    private func background(configuration: Configuration) -> some View {
        Group {
            switch kind {
            case .primary:
                Color.careVoicePrimary.opacity(configuration.isPressed ? 0.82 : 1)
            case .secondary:
                Color.careVoicePrimary.opacity(configuration.isPressed ? 0.16 : 0.10)
            case .destructive:
                Color.riskIntervention.opacity(configuration.isPressed ? 0.82 : 1)
            }
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
