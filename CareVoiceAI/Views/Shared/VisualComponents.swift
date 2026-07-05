import SwiftUI

struct StickerIcon: View {
    let systemImage: String
    var size: CGFloat = 36
    var iconSize: CGFloat = 16
    var tint: Color = .careVoicePrimary

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.2), tint.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(CVCornerRadius.sticker)
            .overlay(
                RoundedRectangle(cornerRadius: CVCornerRadius.sticker)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.12), radius: 4, x: 0, y: 2)
            .accessibilityHidden(true)
    }
}

struct StickerLabel: View {
    let text: String
    let systemImage: String
    var font: Font = .caption.weight(.semibold)
    var tint: Color = .careVoicePrimary

    var body: some View {
        HStack(spacing: CVSpacing.sm) {
            StickerIcon(systemImage: systemImage, size: 28, iconSize: 13, tint: tint)
            Text(text)
                .font(font)
                .foregroundColor(.secondary)
        }
    }
}

struct SectionHeaderView: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    var tint: Color = .careVoicePrimary

    var body: some View {
        HStack(alignment: .top, spacing: CVSpacing.md) {
            StickerIcon(systemImage: systemImage, size: 40, iconSize: 18, tint: tint)
            VStack(alignment: .leading, spacing: CVSpacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct AnimatedHeroHeader: View {
    let title: String
    let subtitle: String
    var logoVariant: CareVoiceLogoVariant = .brand

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            CareVoiceLogo(variant: logoVariant, size: 88, showPulse: false)
                .cvStaggeredAppear(index: 0, isVisible: appeared)

            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.primary)
                .cvStaggeredAppear(index: 1, isVisible: appeared)

            Text(subtitle)
                .font(.title3)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .cvStaggeredAppear(index: 2, isVisible: appeared)
        }
        .onAppear {
            appeared = true
        }
    }
}

struct PulsingIcon: View {
    let systemImage: String
    var size: CGFloat = 38
    var tint: Color = .careVoicePrimary

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(tint)
            .scaleEffect(pulse && !reduceMotion ? 1.06 : 1)
            .opacity(pulse && !reduceMotion ? 1 : 0.82)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

struct RoleCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct AuthLoginHeader: View {
    let title: String
    var logoVariant: CareVoiceLogoVariant = .brand

    @State private var appeared = false

    var body: some View {
        HStack(alignment: .center, spacing: CVSpacing.md) {
            CareVoiceLogo(variant: logoVariant, size: 56, showPulse: false)
            Text(title)
                .font(CVFont.patientTitle)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, CVSpacing.lg)
        .cvStaggeredAppear(index: 0, isVisible: appeared)
        .onAppear { appeared = true }
    }
}

struct PhoneCallChip: View {
    let title: String
    let phoneNumber: String
    var systemImage: String = "phone.fill"
    var tint: Color = .careVoicePrimary
    var onCalled: (() -> Void)?

    @State private var callFailureMessage: String?

    var body: some View {
        Button {
            HapticsManager.tap()
            switch PhoneDialer.dial(phoneNumber) {
            case .success:
                onCalled?()
            case .failure(let failure):
                callFailureMessage = callFailureMessage(for: failure)
            }
        } label: {
            HStack(spacing: CVSpacing.sm) {
                StickerIcon(systemImage: systemImage, size: 32, iconSize: 14, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(tint)
                    Text(phoneNumber)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                }
                Spacer(minLength: 0)
                Image(systemName: "phone.arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(tint)
            }
            .padding(CVSpacing.md)
            .background(tint.opacity(0.08))
            .cornerRadius(CVCornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CVCornerRadius.sm)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("\(title), \(phoneNumber)")
        .alert(
            L10n.text("staff.call_failed.title"),
            isPresented: Binding(
                get: { callFailureMessage != nil },
                set: { if !$0 { callFailureMessage = nil } }
            )
        ) {
            Button(L10n.text("common.ok"), role: .cancel) {
                callFailureMessage = nil
            }
        } message: {
            Text(callFailureMessage ?? "")
        }
    }

    private func callFailureMessage(for failure: PhoneDialer.Failure) -> String {
        switch failure {
        case .invalidNumber:
            return L10n.text("staff.call_failed.invalid_number")
        case .unavailable:
            return L10n.text("staff.call_failed.unavailable")
        }
    }
}

struct QuickActionSticker: View {
    let title: String
    let systemImage: String
    var tint: Color = .careVoicePrimary

    var body: some View {
        HStack(spacing: CVSpacing.sm) {
            StickerIcon(systemImage: systemImage, size: 32, iconSize: 14, tint: tint)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)
        }
        .padding(.horizontal, CVSpacing.sm)
        .padding(.vertical, CVSpacing.xs)
        .background(tint.opacity(0.08))
        .cornerRadius(CVCornerRadius.sm)
    }
}

struct DemoModeBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: CVSpacing.sm) {
            Image(systemName: "iphone.and.arrow.forward")
                .foregroundColor(.riskAttention)
            Text(L10n.text("settings.demo_mode_on_hint"))
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(CVSpacing.md)
        .background(Color.riskAttention.opacity(0.10))
        .cornerRadius(8)
    }
}