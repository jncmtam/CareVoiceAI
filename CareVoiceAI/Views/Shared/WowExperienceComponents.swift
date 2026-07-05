import SwiftUI

struct CriticalAlertBanner: View {
    let patient: PatientSummary
    let onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            HStack(alignment: .top, spacing: CVSpacing.sm) {
                StickerIcon(systemImage: "exclamationmark.triangle.fill", size: 44, iconSize: 20, tint: .riskIntervention)
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(L10n.text("staff.critical.banner_title"))
                        .font(.headline)
                        .foregroundColor(.riskIntervention)
                    Text(patient.fullName)
                        .font(.title3.weight(.bold))
                    Text(patient.patientCode)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let summary = patient.latestSummary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                    if let reasons = patient.alertReasons?.prefix(2), !reasons.isEmpty {
                        ForEach(Array(reasons), id: \.self) { reason in
                            Label(reason, systemImage: "info.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if patient.caregiverAlertSentAt != nil {
                        Label(L10n.text("staff.caregiver_alert_sent"), systemImage: "message.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.riskAttention)
                    }
                }
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel(L10n.cancel)
                }
            }

            HStack(spacing: CVSpacing.sm) {
                if let phone = patient.patientPhone {
                    UrgentCallButton(
                        title: L10n.text("staff.call_patient"),
                        phoneNumber: phone,
                        systemImage: "phone.fill",
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

            NavigationLink(destination: PatientDetailView(patientId: patient.patientId)) {
                Label(L10n.text("staff.critical.open_chart"), systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(CVButtonStyle(kind: .secondary))
        }
        .padding(CVSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CVCornerRadius.md)
                .fill(Color.riskIntervention.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CVCornerRadius.md)
                .stroke(Color.riskIntervention.opacity(0.45), lineWidth: 2)
        )
    }
}

struct UrgentCallButton: View {
    enum Style {
        case primary
        case secondary
    }

    let title: String
    let phoneNumber: String
    var systemImage: String = "phone.fill"
    var tint: Color = .riskIntervention
    var style: Style = .primary
    var onCalled: (() -> Void)?

    @State private var callFailureMessage: String?

    var body: some View {
        Button {
            HapticsManager.urgent()
            switch PhoneDialer.dial(phoneNumber) {
            case .success:
                onCalled?()
            case .failure(let failure):
                callFailureMessage = failureMessage(for: failure)
            }
        } label: {
            HStack(spacing: CVSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.body.weight(.bold))
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundColor(style == .primary ? .white : tint)
            .background(style == .primary ? tint : tint.opacity(0.12))
            .cornerRadius(CVCornerRadius.sm)
        }
        .buttonStyle(BorderlessButtonStyle())
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

    private func failureMessage(for failure: PhoneDialer.Failure) -> String {
        switch failure {
        case .invalidNumber:
            return L10n.text("staff.call_failed.invalid_number")
        case .unavailable:
            return L10n.text("staff.call_failed.unavailable")
        }
    }
}

struct CaregiverNotifiedBanner: View {
    let caregiverName: String?
    let sentAt: Date

    var body: some View {
        HStack(spacing: CVSpacing.md) {
            StickerIcon(systemImage: "message.fill", size: 40, iconSize: 18, tint: .riskAttention)
            VStack(alignment: .leading, spacing: CVSpacing.xs) {
                Text(L10n.text("patient.caregiver_notified.title"))
                    .font(.headline)
                Text(
                    caregiverName.map { String(format: L10n.text("patient.caregiver_notified.body_named"), $0) }
                        ?? L10n.text("patient.caregiver_notified.body")
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                Text(DateFormatters.shortDateTime.string(from: sentAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .cvGlossyCard(elevation: .raised)
    }
}

struct ImpactMetricStrip: View {
    let minutesSaved: Int
    let callsAvoided: Int
    let completionPercent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.text("staff.impact.title"),
                systemImage: "chart.line.uptrend.xyaxis", subtitle: L10n.text("staff.impact.subtitle"),
                tint: .riskNormal
            )
            HStack(spacing: CVSpacing.sm) {
                ImpactChip(value: "\(minutesSaved)+", label: L10n.text("staff.impact.minutes"), tint: .careVoicePrimary)
                ImpactChip(value: "\(callsAvoided)", label: L10n.text("staff.impact.calls"), tint: .riskAttention)
                ImpactChip(value: "\(completionPercent)%", label: L10n.text("staff.impact.checkins"), tint: .riskNormal)
            }
        }
        .cvGlossyCard(elevation: .raised)
    }
}

private struct ImpactChip: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: CVSpacing.xs) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(tint)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(CVSpacing.sm)
        .background(tint.opacity(0.10))
        .cornerRadius(CVCornerRadius.sm)
    }
}

struct MorningProgressCard: View {
    @ObservedObject var tracker: MorningRoutineTracker

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            SectionHeaderView(
                title: L10n.text("patient.morning.title"),
                systemImage: "sun.max.fill", subtitle: String(format: L10n.text("patient.morning.progress"), tracker.completedSteps, MorningRoutineTracker.totalSteps),
                tint: .riskAttention
            )
            ProgressView(value: tracker.progressFraction)
                .tint(.careVoicePrimary)
            VStack(spacing: CVSpacing.sm) {
                MorningStepLink(
                    step: 1,
                    title: L10n.todayCheckin,
                    systemImage: "heart.text.square.fill",
                    isDone: tracker.checkinCompleted,
                    destination: AnyView(TodayCheckinView())
                )
                MorningStepLink(
                    step: 2,
                    title: L10n.medications,
                    systemImage: "pills.fill",
                    isDone: tracker.medicationCompleted,
                    destination: AnyView(MedicationListView())
                )
                MorningStepLink(
                    step: 3,
                    title: L10n.text("face.title_short"),
                    systemImage: "faceid",
                    isDone: tracker.faceVerifyCompleted,
                    destination: AnyView(FaceVerificationPlaceholderView())
                )
            }
            if tracker.isMorningComplete {
                Label(L10n.text("patient.morning.complete"), systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.riskNormal)
            }
        }
        .cvGlossyCard(elevation: .hero)
        .onAppear { tracker.resetIfNewDay() }
    }
}

private struct MorningStepLink: View {
    let step: Int
    let title: String
    let systemImage: String
    let isDone: Bool
    let destination: AnyView

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: CVSpacing.md) {
                ZStack {
                    Circle()
                        .fill(isDone ? Color.riskNormal.opacity(0.18) : Color.careVoicePrimary.opacity(0.12))
                        .frame(width: 32, height: 32)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.riskNormal)
                    } else {
                        Text("\(step)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.careVoicePrimary)
                    }
                }
                Label(title, systemImage: systemImage)
                    .font(CVFont.patientAction)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .frame(minHeight: 52)
            .padding(.horizontal, CVSpacing.sm)
            .background(Color.appSurface.opacity(0.6))
            .cornerRadius(CVCornerRadius.sm)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CheckinFlowStepBar: View {
    enum Step: Int {
        case listen = 1
        case speak = 2
        case confirm = 3
    }

    let activeStep: Step
    var isListening: Bool = false
    var showsConfirmStep = true

    var body: some View {
        HStack(spacing: CVSpacing.xs) {
            stepChip(
                number: 1,
                title: L10n.text("patient.checkin.step_listen"),
                isActive: activeStep == .listen,
                isHighlighted: isListening
            )
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.bold))
                .foregroundColor(.secondary)
            stepChip(
                number: 2,
                title: L10n.text("patient.checkin.step_speak"),
                isActive: activeStep == .speak || activeStep == .confirm,
                isHighlighted: activeStep == .speak
            )
            if showsConfirmStep {
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.secondary)
                stepChip(
                    number: 3,
                    title: L10n.text("patient.checkin.step_confirm"),
                    isActive: activeStep == .confirm,
                    isHighlighted: activeStep == .confirm
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepChip(number: Int, title: String, isActive: Bool, isHighlighted: Bool) -> some View {
        HStack(spacing: CVSpacing.xs) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundColor(isActive ? .white : .careVoicePrimary)
                .frame(width: 22, height: 22)
                .background(isActive ? Color.careVoicePrimary : Color.careVoicePrimary.opacity(0.12))
                .clipShape(Circle())
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, CVSpacing.sm)
        .padding(.vertical, CVSpacing.xs)
        .background(isHighlighted ? Color.careVoicePrimary.opacity(0.12) : Color.appSurface.opacity(0.7))
        .cornerRadius(CVCornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CVCornerRadius.sm)
                .stroke(isActive ? Color.careVoicePrimary.opacity(0.35) : Color.clear, lineWidth: 1.5)
        )
    }
}

struct PulseBorderModifier: ViewModifier {
    let active: Bool
    let color: Color

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: CVCornerRadius.sm)
                    .stroke(color.opacity(active ? 0.45 : 0), lineWidth: 2)
            )
    }
}

extension View {
    func pulseBorder(active: Bool, color: Color = .riskIntervention) -> some View {
        modifier(PulseBorderModifier(active: active, color: color))
    }
}
