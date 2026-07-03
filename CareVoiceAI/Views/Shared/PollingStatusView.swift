import SwiftUI

struct PollingStatusView: View {
    let title: String
    var progress: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.sm) {
            HStack(spacing: CVSpacing.sm) {
                ProgressView()
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
            }
            if let progress {
                ProgressView(value: Double(progress), total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: .careVoicePrimary))
                Text("\(progress)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(CVSpacing.md)
        .background(Color.careVoicePrimary.opacity(0.08))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
    }
}
