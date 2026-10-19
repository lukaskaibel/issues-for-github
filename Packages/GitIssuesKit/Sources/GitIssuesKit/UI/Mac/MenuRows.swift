#if os(macOS)
import AppKit
import Observation
import SwiftUI

/// The row a menu, a picker or a grid lights up, under the pointer or the arrow keys, and the row whose submenu is
/// open. A row asks only about itself, so moving the light redraws the row it leaves and the row it enters and
/// nothing else: the list around them keeps what it worked out, however long it is, and the light follows the pointer
/// within the frame.
@MainActor @Observable
final class MenuCursor<Key: Hashable & Sendable> {
    @ObservationIgnored private var lit: Key?
    @ObservationIgnored private var opened: Key?
    /// Whether the open submenu took the keyboard: opened with the keys it did, opened under the pointer it didn't.
    @ObservationIgnored private(set) var openTakesKey = true
    /// Counts the moves made with the keys, so a list can scroll the lit row into view; the pointer is on it already
    /// when it moves.
    private(set) var keyMoves = 0

    init(_ key: Key? = nil) {
        lit = key
    }

    /// The lit row, for key presses and actions. A view that reads it in its body is redrawn on every move; rows ask
    /// `isLit` instead.
    var key: Key? {
        get {
            access(keyPath: \.key)
            return lit
        }
        set {
            guard newValue != lit else { return }
            let old = lit
            withMutation(keyPath: \.key) {
                notify([old, newValue], { \.[lit: $0] }) { lit = newValue }
            }
        }
    }

    /// The row whose submenu is open.
    var open: Key? {
        get {
            access(keyPath: \.open)
            return opened
        }
        set {
            guard newValue != opened else { return }
            let old = opened
            withMutation(keyPath: \.open) {
                notify([old, newValue], { \.[open: $0] }) { opened = newValue }
            }
        }
    }

    subscript(lit key: Key) -> Bool {
        access(keyPath: \.[lit: key])
        return lit == key
    }

    subscript(open key: Key) -> Bool {
        access(keyPath: \.[open: key])
        return opened == key
    }

    /// Whether this row shows lit: under the pointer or the keys, or with its submenu open.
    func isLit(_ key: Key) -> Bool {
        self[lit: key] || self[open: key]
    }

    /// Lights the row the pointer enters and puts out the one it leaves, unless the pointer is on another by then.
    func hover(_ key: Key, _ inside: Bool) {
        if inside {
            self.key = key
        } else if lit == key {
            self.key = nil
        }
    }

    /// Moves the light with the arrow keys through `keys`, wrapping around at the ends.
    func step(_ delta: Int, through keys: [Key]) {
        guard let next = menuStep(lit.flatMap { keys.firstIndex(of: $0) }, by: delta, count: keys.count) else { return }
        moveByKeys(to: keys[next])
    }

    /// Lights a row from the keys, so the list scrolls to it.
    func moveByKeys(to key: Key?) {
        self.key = key
        keyMoves += 1
    }

    /// Opens the row's submenu; `takesKey` gives the submenu the keyboard.
    func openSubmenu(_ key: Key, takesKey: Bool) {
        openTakesKey = takesKey
        open = key
    }

    private func notify(_ keys: [Key?], _ path: (Key) -> KeyPath<MenuCursor, Bool>, _ change: () -> Void) {
        let paths = keys.compactMap { $0 }.map(path)
        for path in paths { _$observationRegistrar.willSet(self, keyPath: path) }
        change()
        for path in paths { _$observationRegistrar.didSet(self, keyPath: path) }
    }
}

/// A row of a menu in a dropdown, such as the account menu: an icon, the title, and on the right a value,
/// a shortcut, a checkmark or the arrow of a submenu. It lights up under the pointer or the arrow keys.
struct MenuRow<Key: Hashable & Sendable>: View {
    var title: String
    var systemImage: String?
    var value: String?
    var shortcut: String?
    var checked = false
    var submenu = false
    var cursor: MenuCursor<Key>
    var key: Key
    /// Lit while its submenu is open, from the menu's own state.
    var open = false
    var action: () -> Void

    var body: some View {
        let active = open || cursor.isLit(key)
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                if submenu {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: PickerRow.height)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? Theme.menuHighlight : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .padding(.horizontal, 6)
        .onHover { cursor.hover(key, $0) }
    }
}

/// The soft accent behind a row or a cell that is lit. It asks the cursor about its own row only, so it is the one
/// thing redrawn when the light arrives or leaves.
struct CursorHighlight<Key: Hashable & Sendable>: View {
    var cursor: MenuCursor<Key>
    var key: Key
    var radius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(cursor.isLit(key) ? Theme.menuHighlight : .clear)
    }
}

/// The line between groups of menu rows.
struct MenuDivider: View {
    var body: some View {
        Rectangle().fill(Theme.popoverBorder).frame(height: 1).padding(.horizontal, 15).padding(.vertical, 5)
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
