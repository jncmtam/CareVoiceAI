import SwiftUI

struct FormField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: CVSpacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            if isSecure {
                SecureField(title, text: $text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minHeight: 48)
            } else {
                TextField(title, text: $text)
                    .keyboardType(keyboardType)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minHeight: 48)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
