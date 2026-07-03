import SwiftUI

struct EmptyStateView: View {
    let title: String
    var systemImage: String = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: CVSpacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text(title)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            if let actionTitle, let action {
                SecondaryButton(title: actionTitle, systemImage: "arrow.clockwise", action: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CVSpacing.xl)
    }
}
