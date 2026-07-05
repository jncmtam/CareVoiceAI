import SwiftUI

struct PollingStatusView: View {
    let title: String
    var systemImage: String = "ellipsis.circle"
    var progress: Int?

    var body: some View {
        HStack(alignment: .top, spacing: CVSpacing.md) {
            PulsingIcon(systemImage: systemImage, size: 28, tint: .careVoicePrimary)
            VStack(alignment: .leading, spacing: CVSpacing.sm) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress {
                    ProgressView(value: Double(progress), total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: .careVoicePrimary))
                    Text("\(progress)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .careVoicePrimary))
                }
            }
        }
        .padding(CVSpacing.md)
        .background(
            LinearGradient(
                colors: [Color.careVoicePrimary.opacity(0.12), Color.careVoicePrimary.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(CVCornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CVCornerRadius.md)
                .stroke(Color.careVoicePrimary.opacity(0.16), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}