import SwiftUI

struct LoadingView: View {
    let title: String
    var systemImage: String?

    var body: some View {
        VStack(spacing: CVSpacing.lg) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 38))
                    .foregroundColor(.careVoicePrimary)
            }
            ProgressView()
            Text(title)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CVSpacing.xl)
        .background(Color.appBackground)
    }
}
