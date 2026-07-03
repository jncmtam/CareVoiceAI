import SwiftUI

struct ErrorBannerView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.sm) {
            HStack(alignment: .top, spacing: CVSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.riskAttention)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let retry {
                Button(action: retry) {
                    Label(L10n.retry, systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.careVoicePrimary)
            }
        }
        .padding(CVSpacing.md)
        .background(Color.riskAttention.opacity(0.12))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
    }
}
