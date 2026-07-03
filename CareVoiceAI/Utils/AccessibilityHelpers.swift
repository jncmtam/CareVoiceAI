import SwiftUI

enum AccessibilityHelpers {
    static func minimumTouchTarget<Content: View>(_ content: Content) -> some View {
        content
            .frame(minWidth: 56, minHeight: 56)
            .contentShape(Rectangle())
    }
}
