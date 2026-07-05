import SwiftUI

struct FormField: View {
    let title: String
    @Binding var text: String
    var systemImage: String?
    var hint: String?
    var errorMessage: String?
    var keyboardType: UIKeyboardType = .default
    var isSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.sm) {
            if let systemImage {
                StickerLabel(text: title, systemImage: systemImage)
            } else {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            if let hint, errorMessage == nil {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                        .keyboardType(keyboardType)
                }
            }
            .padding(.horizontal, CVSpacing.md)
            .frame(minHeight: 50)
            .background(Color.appSurface)
            .cornerRadius(CVCornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CVCornerRadius.sm)
                    .stroke(
                        (errorMessage == nil ? Color.careVoicePrimary.opacity(0.14) : Color.riskIntervention.opacity(0.55)),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.careVoicePrimary.opacity(0.06), radius: 4, x: 0, y: 2)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.riskIntervention)
            }
        }
        .accessibilityElement(children: .contain)
    }
}