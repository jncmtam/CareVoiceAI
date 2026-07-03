import SwiftUI

struct RiskBadge: View {
    let level: RiskLevel?

    var body: some View {
        HStack(spacing: CVSpacing.xs) {
            Image(systemName: iconName)
            Text(L10n.riskLabel(level))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, CVSpacing.sm)
        .padding(.vertical, CVSpacing.xs)
        .foregroundColor(color)
        .background(color.opacity(0.12))
        .cornerRadius(8)
        .accessibilityLabel(L10n.riskLabel(level))
    }

    private var color: Color {
        switch level {
        case .normal:
            return .riskNormal
        case .attention:
            return .riskAttention
        case .intervention:
            return .riskIntervention
        case .none:
            return .secondary
        }
    }

    private var iconName: String {
        switch level {
        case .normal:
            return "checkmark.circle.fill"
        case .attention:
            return "exclamationmark.triangle.fill"
        case .intervention:
            return "cross.case.fill"
        case .none:
            return "clock.fill"
        }
    }
}
