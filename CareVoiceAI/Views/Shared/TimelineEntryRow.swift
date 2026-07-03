import SwiftUI

struct TimelineEntryRow: View {
    let entry: TimelineEntry
    var onViewed: (() -> Void)?
    var onCallback: (() -> Void)?
    var onNote: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: CVSpacing.xs) {
                    Text(DateFormatters.shortDateTime.string(from: entry.occurredAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                Spacer()
                RiskBadge(level: entry.riskLevel)
            }

            if entry.status == .analyzing || entry.status == .processing || entry.status == .transcribing {
                PollingStatusView(title: entry.displayMessage ?? L10n.analyzingResponse, progress: nil)
            } else {
                if let summary = entry.summary {
                    Text(summary)
                        .font(.body)
                        .foregroundColor(.primary)
                }
                if let transcript = entry.transcript {
                    Text(transcript)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
                if let reasons = entry.riskReasons, !reasons.isEmpty {
                    VStack(alignment: .leading, spacing: CVSpacing.xs) {
                        ForEach(reasons, id: \.self) { reason in
                            Label(reason, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if entry.status == .completed {
                HStack(spacing: CVSpacing.sm) {
                    Button(action: { onViewed?() }) {
                        Label(L10n.markViewed, systemImage: "checkmark.circle")
                    }
                    Button(action: { onCallback?() }) {
                        Label(L10n.callBack, systemImage: "phone.fill")
                    }
                    Button(action: { onNote?() }) {
                        Label(L10n.addNote, systemImage: "square.and.pencil")
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.careVoicePrimary)
            }
        }
        .cvCard()
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch entry.type {
        case .checkinResponse:
            return L10n.text("timeline.checkin")
        case .hotlineQuestion:
            return L10n.text("timeline.hotline")
        case .medicationUpdate:
            return L10n.text("timeline.medication")
        case .appointment:
            return L10n.text("timeline.appointment")
        }
    }
}
