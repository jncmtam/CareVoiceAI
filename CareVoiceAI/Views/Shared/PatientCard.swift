import SwiftUI

struct PatientCard: View {
    let patient: PatientSummary
    var showQuickDial = false
    var appliesCardStyle = true

    var body: some View {
        cardContent
            .modifier(OptionalCardStyle(enabled: appliesCardStyle))
    }

    @ViewBuilder
    private var cardContent: some View {
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

            if let reasons = patient.alertReasons, !reasons.isEmpty {
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    ForEach(reasons.prefix(2), id: \.self) { reason in
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.riskAttention)
                    }
                }
            }

            HStack(spacing: CVSpacing.sm) {
                if let age = patient.age {
                    Label("\(age)", systemImage: "calendar")
                }
                if let count = patient.unreadAlertCount, count > 0 {
                    Label("\(count)", systemImage: "bell.badge.fill")
                        .foregroundColor(.riskIntervention)
                }
                if patient.caregiverAlertSentAt != nil {
                    Label(L10n.text("staff.caregiver_alert_sent"), systemImage: "message.fill")
                        .foregroundColor(.riskAttention)
                }
                if let missed = patient.missedMedicationDoses, missed > 0 {
                    Label("\(missed)", systemImage: "pills.fill")
                        .foregroundColor(.riskIntervention)
                }
                Spacer()
                if let date = patient.latestCheckinAt {
                    Text(DateFormatters.shortDateTime.string(from: date))
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if showQuickDial {
                PatientQuickDialRow(patient: patient)
            }
        }
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

struct PatientQuickDialRow: View {
    let patient: PatientSummary

    var body: some View {
        if patient.latestRiskLevel == .intervention || patient.latestRiskLevel == .attention {
            HStack(spacing: CVSpacing.sm) {
                if let phone = patient.patientPhone {
                    UrgentCallButton(
                        title: L10n.text("staff.call_patient"),
                        phoneNumber: phone,
                        tint: .riskIntervention,
                        style: .primary
                    )
                }
                if let caregiver = patient.caregiverPhone {
                    UrgentCallButton(
                        title: L10n.text("staff.call_caregiver"),
                        phoneNumber: caregiver,
                        systemImage: "phone.badge.waveform.fill",
                        tint: .riskAttention,
                        style: .secondary
                    )
                }
            }
        }
    }
}

private struct OptionalCardStyle: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.cvCard()
        } else {
            content
        }
    }
}
