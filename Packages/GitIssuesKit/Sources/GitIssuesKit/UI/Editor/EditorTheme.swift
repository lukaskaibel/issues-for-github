#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// The editor's colours: the app's Theme as AppKit and UIKit colours, which the text system draws with, plus the few
/// that only Markdown needs. Every one has a light and a dark value.
enum EditorTheme {
    static let panel = NSColor(Theme.panel)
    static let card = NSColor(Theme.card)
    static let cardBorder = NSColor(Theme.cardBorder)
    static let control = NSColor(Theme.control)

    static let text = NSColor(Theme.text)
    static let textSecondary = NSColor(Theme.textSecondary)
    static let textTertiary = NSColor(Theme.textTertiary)
    static let textBody = NSColor(Theme.textBody)
    /// Markdown punctuation shown next to the caret.
    static let faint = NSColor(light: 0xA3A7AF, dark: 0x5A5E66)

    static let accent = NSColor(Theme.accent)
    static let positive = NSColor(Theme.positive)
    static let warning = NSColor(Theme.warning)
    static let red = NSColor(Theme.overdue)
    static let purple = NSColor(Theme.epic)
    static let blue = NSColor(light: 0x2F86B5, dark: 0x5AB0D8)

    static let code = NSColor(light: 0xF5F5F7, dark: 0x262628)
    static let codeBorder = NSColor(light: 0xE8E8EB, dark: 0x313134)
    static let inlineCode = NSColor(light: 0xEFEFF2, dark: 0x2E2E31)
    static let tableHeader = NSColor(light: 0xEDEEF2, dark: 0x333336)
    static let tableStripe = NSColor(light: 0xF4F5F8, dark: 0x2A2A2D)
}

/// GitHub's alerts (`> [!NOTE]`), in GitHub's colours and with its symbols.
enum CalloutStyle {
    /// The five kinds GitHub draws; any other `[!word]` stays a quote, as on GitHub.
    static let types: Set<String> = ["note", "tip", "important", "warning", "caution"]

    static func color(_ type: String) -> NSColor {
        switch type {
        case "tip": EditorTheme.positive
        case "important": EditorTheme.purple
        case "warning": EditorTheme.warning
        case "caution": EditorTheme.red
        default: EditorTheme.blue
        }
    }

    static func symbol(_ type: String) -> String {
        switch type {
        case "tip": "lightbulb"
        case "important": "exclamationmark.bubble"
        case "warning": "exclamationmark.triangle"
        case "caution": "exclamationmark.octagon"
        default: "info.circle"
        }
    }

    static func title(_ type: String) -> String {
        switch type {
        case "tip": String(localized: .alertTip)
        case "important": String(localized: .alertImportant)
        case "warning": String(localized: .alertWarning)
        case "caution": String(localized: .alertCaution)
        default: String(localized: .alertNote)
        }
    }
}
