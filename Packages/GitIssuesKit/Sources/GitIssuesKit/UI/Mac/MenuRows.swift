#if os(macOS)
import AppKit
import SwiftUI

/// A row of a menu in a dropdown, such as the account menu: an icon, the title, and on the right a value,
/// a shortcut, a checkmark or the arrow of a submenu. It lights up under the pointer or the arrow keys.
struct MenuRow: View {
    var title: String
    var systemImage: String?
    var value: String?
    var shortcut: String?
    var checked = false
    var submenu = false
    var active: Bool
    var action: () -> Void
    var onHover: (Bool) -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let systemImage { Image(systemName: systemImage) } else { Color.clear }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16, height: 16)
                Text(title).lineLimit(1)
                Spacer(minLength: 12)
                if let value {
                    Text(value).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                if let shortcut {
                    Text(shortcut).font(.small).foregroundStyle(Theme.textTertiary)
                }
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textBody)
                }
                if submenu {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? Theme.popoverSelected : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .padding(.horizontal, 4)
        .onHover(perform: onHover)
    }
}

/// The line between groups of menu rows.
struct MenuDivider: View {
    var body: some View {
        Rectangle().fill(Theme.popoverBorder).frame(height: 1).padding(.vertical, 4)
    }
}

/// Moves through a menu's rows with the arrow keys, wrapping around at the ends; from nothing picked, down
/// starts at the top and up at the bottom.
func menuStep(_ index: Int?, by delta: Int, count: Int) -> Int? {
    guard count > 0 else { return nil }
    guard let index else { return delta > 0 ? 0 : count - 1 }
    return (index + delta + count) % count
}

/// Gives a dropdown menu the keyboard: ↑ and ↓ move, Return or Space picks, → opens a submenu, ← and Escape
/// close. A dropdown without a text field otherwise has nothing that takes key presses.
struct MenuKeys: NSViewRepresentable {
    var onMove: (Int) -> Void
    var onActivate: () -> Void
    var onOpen: () -> Void = {}
    var onBack: (() -> Void)?

    func makeNSView(context: Context) -> KeyView { KeyView() }

    func updateNSView(_ view: KeyView, context: Context) {
        view.onMove = onMove
        view.onActivate = onActivate
        view.onOpen = onOpen
        view.onBack = onBack
    }

    final class KeyView: NSView {
        var onMove: (Int) -> Void = { _ in }
        var onActivate: () -> Void = {}
        var onOpen: () -> Void = {}
        var onBack: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }
        // Never in the way of clicks on the rows it sits behind.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // The panel is made key right after its content is in place.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 125: onMove(1)
            case 126: onMove(-1)
            case 36, 76, 49: onActivate()
            case 124: onOpen()
            case 123: onBack?()
            case 53: window?.cancelOperation(nil)
            default: break
            }
        }
    }
}
#endif
