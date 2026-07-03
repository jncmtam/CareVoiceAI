import SwiftUI

struct PatientCard: View {
    let patient: PatientSummary

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            HStack(alignment: .top, spacing: CVSpacing.md) {
                Circle()
                    .fill(riskColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(riskColor)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(patient.fullName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text(patient.patientCode)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: CVSpacing.sm)
                RiskBadge(level: patient.latestRiskLevel)
            }

            if let summary = patient.latestSummary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(3)
            }

            HStack(spacing: CVSpacing.sm) {
                if let age = patient.age {
                    Label("\(age)", systemImage: "calendar")
                }
                if let count = patient.unreadAlertCount, count > 0 {
                    Label("\(count)", systemImage: "bell.badge.fill")
                        .foregroundColor(.riskIntervention)
                }
                Spacer()
                if let date = patient.latestCheckinAt {
                    Text(DateFormatters.shortDateTime.string(from: date))
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .cvCard()
        .accessibilityElement(children: .combine)
    }

    private var riskColor: Color {
        switch patient.latestRiskLevel {
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
}
