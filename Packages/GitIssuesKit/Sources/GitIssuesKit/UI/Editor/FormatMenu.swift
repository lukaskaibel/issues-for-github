import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The Markdown being typed in, if any: the Format menu offers its commands only then, and sends them there.
@MainActor
@Observable
final class MarkdownFocus {
    static let shared = MarkdownFocus()
    private(set) var isEditing = false
    @ObservationIgnored private(set) weak var textView: MarkdownTextView?

    /// Going from one text to another may tell of the new one before the old one is left.
    func focusChanged(_ textView: MarkdownTextView, to focused: Bool) {
        if focused {
            self.textView = textView
        } else if self.textView === textView {
            self.textView = nil
        }
        isEditing = self.textView != nil
    }
}

#if os(macOS)
/// The Format menu, with Notebook's shortcuts: each command goes to the Markdown text being typed in. On iPad the text
/// view offers the same shortcuts itself, listed while ⌘ is held: commands in the system's Format menu don't get them
/// there.
struct FormatCommands: Commands {
    /// Read by the scene from `MarkdownFocus`: a scene's body follows its changes, a `Commands` body doesn't.
    var isEditing: Bool

    var body: some Commands {
        CommandMenu(.formatMenu) {
            ForEach(Array(FormatShortcut.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group, id: \.name) { shortcut in
                    Button {
                        guard let textView = MarkdownFocus.shared.textView else { return }
                        NSApp.sendAction(shortcut.action, to: textView, from: nil)
                    } label: {
                        Label(shortcut.name, systemImage: shortcut.symbol)
                    }
                    .keyboardShortcut(KeyEquivalent(shortcut.key), modifiers: shortcut.modifiers)
                    .disabled(!isEditing)
                }
            }
        }
    }
}
#endif

/// A Format menu command and its shortcut. The text being typed in takes these shortcuts itself too: on the Mac the
/// menu may not know yet that text has just been clicked into, and would let the key press go by.
struct FormatShortcut {
    let name: String
    let symbol: String
    let action: Selector
    let key: Character
    let modifiers: EventModifiers

    /// As the menu shows them, between dividers. On iPad, Bold and Italic are the system's own.
    static let groups: [[FormatShortcut]] = {
        var inline = [
            FormatShortcut(.strikethrough, #selector(MarkdownTextView.toggleStrikethrough(_:)), "x", [.command, .shift]),
            FormatShortcut(.code, #selector(MarkdownTextView.toggleInlineCode(_:)), "e"),
            FormatShortcut(.link, #selector(MarkdownTextView.addLink(_:)), "l"),
        ]
        #if os(macOS)
        inline.insert(contentsOf: [
            FormatShortcut(.bold, #selector(MarkdownTextView.toggleBoldface(_:)), "b"),
            FormatShortcut(.italic, #selector(MarkdownTextView.toggleItalics(_:)), "i"),
        ], at: 0)
        #endif
        return [
            inline,
            [
                FormatShortcut(.title, #selector(MarkdownTextView.makeTitle(_:)), "t", [.command, .shift]),
                FormatShortcut(.heading, #selector(MarkdownTextView.makeHeading(_:)), "h", [.command, .shift]),
                FormatShortcut(.subheading, #selector(MarkdownTextView.makeSubheading(_:)), "j", [.command, .shift]),
                FormatShortcut(.body, #selector(MarkdownTextView.makeBody(_:)), "b", [.command, .shift]),
            ],
            [
                FormatShortcut(.checklist, #selector(MarkdownTextView.makeChecklist(_:)), "l", [.command, .shift]),
                FormatShortcut(name: String(localized: .markAsChecked), symbol: "checkmark.square", action: #selector(MarkdownTextView.markChecked(_:)), key: "u", modifiers: [.command, .shift]),
                FormatShortcut(.bulletedList, #selector(MarkdownTextView.makeBulletedList(_:)), "7", [.command, .shift]),
                FormatShortcut(.numberedList, #selector(MarkdownTextView.makeNumberedList(_:)), "9", [.command, .shift]),
                FormatShortcut(.quote, #selector(MarkdownTextView.makeQuote(_:)), "'"),
            ],
            [
                FormatShortcut(.indent, #selector(MarkdownTextView.indentLines(_:)), "]", [.command, .option]),
                FormatShortcut(.outdent, #selector(MarkdownTextView.outdentLines(_:)), "[", [.command, .option]),
            ],
        ]
    }()

    #if os(macOS)
    /// The command a key press stands for, if it is one of these shortcuts.
    @MainActor
    static func action(for event: NSEvent) -> Selector? {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags.contains(.command) else { return nil }
        // The key as written on it, so ⇧⌘7 is "7" whichever character Shift gives it, or what it types, so ⌥⌘6 is
        // ⌥⌘] where Option and 6 make "]".
        let keys = [event.characters(byApplyingModifiers: []), event.charactersIgnoringModifiers?.lowercased(), event.characters].compactMap { $0?.first }
        return groups.joined().first { keys.contains($0.key) && $0.flags == flags }?.action
    }

    private var flags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }
    #else
    /// The shortcut as a key command for the text view, named for the list shown while ⌘ is held.
    var keyCommand: UIKeyCommand {
        var flags: UIKeyModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.alternate) }
        if modifiers.contains(.control) { flags.insert(.control) }
        let command = UIKeyCommand(title: name, image: UIImage(systemName: symbol), action: action, input: String(key), modifierFlags: flags)
        command.wantsPriorityOverSystemBehavior = true
        return command
    }
    #endif
}

extension FormatShortcut {
    init(_ command: FormatCommand, _ action: Selector, _ key: Character, _ modifiers: EventModifiers = .command) {
        self.init(name: command.name, symbol: command.symbol, action: action, key: key, modifiers: modifiers)
    }
}
