import SwiftUI

struct LoadingView: View {
    let title: String
    var logoVariant: CareVoiceLogoVariant?
    var systemImage: String?

    @State private var appeared = false

    var body: some View {
        VStack(spacing: CVSpacing.lg) {
            if let logoVariant {
                CareVoiceLogo(variant: logoVariant, size: 72, showPulse: false)
                    .cvStaggeredAppear(index: 0, isVisible: appeared)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.careVoicePrimary)
            }
            ProgressView()
                .scaleEffect(1.1)
                .cvStaggeredAppear(index: 1, isVisible: appeared)
            Text(title)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .cvStaggeredAppear(index: 2, isVisible: appeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CVSpacing.xl)
        .background(Color.appBackground)
        .onAppear { appeared = true }
    }
}