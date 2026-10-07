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
        image { _, rect in
            if level == .urgent {
                let badge = NSRect(x: rect.midX - 6, y: rect.midY - 6, width: 12, height: 12)
                NSColor(Theme.urgent).setFill()
                NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()
                let mark = NSAttributedString(string: "!", attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .heavy),
                    .foregroundColor: NSColor(Theme.onColor),
                ])
                let markSize = mark.size()
                mark.draw(at: NSPoint(x: badge.midX - markSize.width / 2, y: badge.midY - markSize.height / 2))
                return
            }
            if level == .none {
                // Three dashes, as Linear shows "No priority".
                NSColor(Theme.textTertiary).setFill()
                for index in 0..<3 {
                    NSBezierPath(roundedRect: NSRect(x: rect.minX + 2 + CGFloat(index) * 4.5, y: rect.midY - 0.75, width: 3, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
                }
                return
            }
            let bars: [(CGFloat, Bool)] = [(4, level >= .low), (7, level >= .medium), (10, level >= .high)]
            for (index, bar) in bars.enumerated() {
                NSColor(bar.1 ? Theme.textBody : Theme.barOff).setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: rect.minX + 1 + CGFloat(index) * 5, y: rect.midY + 5 - bar.0, width: 3, height: bar.0),
                    xRadius: 1, yRadius: 1
                ).fill()
            }
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
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    /// A symbol in a colour of its own, such as the flags for blocked and blocking issues.
    static func symbol(_ name: String, color: Color) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(color)]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    static var blocked: NSImage? { symbol("flag.fill", color: Theme.blocked) }
    static var blocking: NSImage? { symbol("flag", color: Theme.urgent) }

    /// The hook and dot of a sub-issue, as on cards.
    static var subIssue: NSImage {
        image { _, rect in
            let s: CGFloat = 1.1
            let origin = NSPoint(x: rect.midX - 6 * s, y: rect.midY - 6 * s)
            let hook = NSBezierPath()
            hook.move(to: NSPoint(x: origin.x + 2.5 * s, y: origin.y + 2 * s))
            hook.line(to: NSPoint(x: origin.x + 2.5 * s, y: origin.y + 6 * s))
            hook.curve(
                to: NSPoint(x: origin.x + 4.5 * s, y: origin.y + 8 * s),
                controlPoint1: NSPoint(x: origin.x + 2.5 * s, y: origin.y + 7.2 * s),
                controlPoint2: NSPoint(x: origin.x + 3.3 * s, y: origin.y + 8 * s)
            )
            hook.line(to: NSPoint(x: origin.x + 6.6 * s, y: origin.y + 8 * s))
            hook.lineWidth = 1.3 * s
            hook.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            hook.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: origin.x + 6.8 * s, y: origin.y + 6.3 * s, width: 3.4 * s, height: 3.4 * s))
            dot.lineWidth = 1.3 * s
            dot.stroke()
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
