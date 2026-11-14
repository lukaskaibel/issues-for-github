#if os(macOS)
import AppKit
import SwiftUI

/// Small images for AppKit menus, drawn with the same glyphs as the rest of the app. They are drawn when
/// shown, so they follow light and dark appearance.
@MainActor
enum MenuIcons {
    static let size = NSSize(width: 16, height: 16)

    static func status(_ glyph: StatusGlyph) -> NSImage {
        image { context, rect in
            StatusPainter.draw(glyph, in: rect.insetBy(dx: 1, dy: 1), cg: context)
        }
    }

    static func priority(_ level: PriorityLevel) -> NSImage {
        image { context, rect in
            if level == .none {
                // Three dashes, as Linear shows "No priority".
                NSColor(Theme.textTertiary).setFill()
                for index in 0..<3 {
                    NSBezierPath(roundedRect: NSRect(x: rect.minX + 2 + CGFloat(index) * 4.5, y: rect.midY - 0.75, width: 3, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
                }
                return
            }
            // The shapes every view of a priority draws (`Marks.priority`), in a box centred in the icon.
            let box = CGRect(x: rect.midX - 7, y: rect.midY - 6, width: 14, height: 12)
            let mark = NSColor(level == .urgent ? Theme.urgent : Theme.textBody)
            context.draw(Marks.priority(level, in: box), mark: mark.cgColor, off: NSColor(Theme.barOff).cgColor, onColor: NSColor(Theme.onColor).cgColor)
            if level == .urgent { Marks.drawUrgentMark(on: Marks.urgentSquare(in: box)) }
        }
    }

    static func avatar(_ person: Person) -> NSImage {
        image { context, rect in
            let circle = rect.insetBy(dx: 1, dy: 1)
            if let url = person.avatarUrl, let picture = AvatarCache.shared.cached(url) {
                context.saveGState()
                NSBezierPath(ovalIn: circle).addClip()
                picture.draw(in: circle, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                context.restoreGState()
            } else {
                NSColor(Avatar.color(for: person.login)).setFill()
                NSBezierPath(ovalIn: circle).fill()
                let initials = NSAttributedString(string: String(person.login.prefix(2)).uppercased(), attributes: [
                    .font: NSFont.systemFont(ofSize: 6.5, weight: .bold),
                    .foregroundColor: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1),
                ])
                let textSize = initials.size()
                initials.draw(at: NSPoint(x: circle.midX - textSize.width / 2, y: circle.midY - textSize.height / 2))
            }
        }
    }

    static func labelDot(_ hex: String) -> NSImage {
        image { _, rect in
            NSColor(Theme.labelColor(hex)).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 4.5, y: rect.midY - 4.5, width: 9, height: 9)).fill()
        }
    }

    static func symbol(_ name: String) -> NSImage? {
        if let image = symbols[name] { return image }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        symbols[name] = image
        return image
    }

    /// Symbols looked up once: a right-click menu asks for a dozen each time it opens.
    private static var symbols: [String: NSImage] = [:]

    /// A symbol in a colour of its own, such as the flags for blocked and blocking issues.
    static func symbol(_ name: String, color: Color) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(color)]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    static func milestone(_ mark: MilestoneMark) -> NSImage {
        image { context, rect in
            PlanningGlyph.drawMilestone(mark, in: rect.insetBy(dx: 1, dy: 1), cg: context)
        }
    }

    static var epic: NSImage {
        image { context, rect in
            PlanningGlyph.drawEpic(in: rect.insetBy(dx: 1, dy: 1), cg: context)
        }
    }

    static var blocked: NSImage? { symbol("flag.fill", color: Theme.blocked) }
    static var blocking: NSImage? { symbol("flag", color: Theme.urgent) }

    /// The hook and ring of a sub-issue, as on cards (`Marks.subIssue`).
    static var subIssue: NSImage {
        image { context, rect in
            let side: CGFloat = 13.2
            let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            context.draw(Marks.subIssue(in: box), mark: NSColor.labelColor.cgColor, onColor: NSColor.labelColor.cgColor)
        }
    }

    private static func image(_ draw: @escaping (CGContext, NSRect) -> Void) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            MainActor.assumeIsolated { draw(context, rect) }
            return true
        }
    }
}
#endif
