import SwiftUI

/// ⌘↵ beside the comment field's send button, while pressing it would send what is written. Hidden, it keeps its place,
/// so the text beside it doesn't wrap anew as it comes and goes.
struct SendShortcutHint: View {
    var isShown: Bool

    var body: some View {
        Text(verbatim: "⌘↵")
            .font(.tiny)
            .foregroundStyle(Theme.textSecondary)
            .opacity(isShown ? 1 : 0)
            .animation(Theme.quick, value: isShown)
            .accessibilityHidden(true)
    }
}
