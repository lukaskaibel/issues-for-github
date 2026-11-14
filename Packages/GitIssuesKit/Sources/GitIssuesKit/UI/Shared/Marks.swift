import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The small marks an issue shows wherever it is drawn: in a view, on a card the board paints, in a row the list paints,
/// in a menu's icon. Each is defined here once, as shapes in the box it is drawn in, so that every place draws the very
/// same mark; only where its colours come from differs, as a painted card keeps them from one paint to the next.
enum Marks {
    /// A shape of a mark and how it is drawn: filled, or stroked in a line of its own.
    struct Shape {
        enum Ink {
            /// The mark's own colour.
            case mark
            /// A second colour, such as the bars of a priority that are off.
            case off
            /// White or black on top of the mark's filled colour, such as the check of a done status.
            case onColor
        }

        var path: Path
        var ink: Ink = .mark
        /// Nil to fill the path.
        var stroke: StrokeStyle?
    }
}

extension GraphicsContext {
    /// Draws a mark's shapes in the colours given for its inks.
    func draw(_ shapes: [Marks.Shape], mark: Color, off: Color = .clear, onColor: Color = Theme.onColor) {
        draw(shapes, shading: .color(mark), off: .color(off), onColor: .color(onColor))
    }

    /// The same with any shading, such as the foreground style of the view it is drawn in.
    func draw(_ shapes: [Marks.Shape], shading: Shading, off: Shading = .color(.clear), onColor: Shading = .color(Theme.onColor)) {
        for shape in shapes {
            let ink: Shading = switch shape.ink {
            case .mark: shading
            case .off: off
            case .onColor: onColor
            }
            if let stroke = shape.stroke {
                self.stroke(shape.path, with: ink, style: stroke)
            } else {
                fill(shape.path, with: ink)
            }
        }
    }
}

extension CGContext {
    /// The same for views drawn with Core Graphics, as the Mac's list and menus are.
    func draw(_ shapes: [Marks.Shape], mark: CGColor, off: CGColor? = nil, onColor: CGColor) {
        saveGState()
        defer { restoreGState() }
        for shape in shapes {
            let color: CGColor? = switch shape.ink {
            case .mark: mark
            case .off: off
            case .onColor: onColor
            }
            guard let color else { continue }
            addPath(shape.path.cgPath)
            if let stroke = shape.stroke {
                setStrokeColor(color)
                setLineWidth(stroke.lineWidth)
                setLineCap(stroke.lineCap)
                setLineJoin(stroke.lineJoin)
                setLineDash(phase: stroke.dashPhase, lengths: stroke.dash)
                strokePath()
            } else {
                setFillColor(color)
                fillPath()
            }
        }
    }
}

// MARK: - Priority

extension Marks {
    /// A priority in a box 14 wide and 12 tall: three bars rising, lit up to the level, or for Urgent a rounded square
    /// in the urgent colour that carries "!" (`urgentMark`, drawn as text on top).
    static func priority(_ level: PriorityLevel, in box: CGRect) -> [Shape] {
        if level == .urgent {
            return [Shape(path: Path(roundedRect: urgentSquare(in: box), cornerRadius: 3))]
        }
        let bars: [(height: CGFloat, on: Bool)] = [(4, level >= .low), (7, level >= .medium), (10, level >= .high)]
        return bars.enumerated().map { index, bar in
            let rect = CGRect(x: box.minX + CGFloat(index) * 5, y: box.maxY - bar.height, width: 3, height: bar.height)
            return Shape(path: Path(roundedRect: rect, cornerRadius: 1), ink: bar.on ? .mark : .off)
        }
    }

    /// Where Urgent's square stands in a priority's box.
    static func urgentSquare(in box: CGRect) -> CGRect {
        CGRect(x: box.midX - 6, y: box.midY - 6, width: 12, height: 12)
    }

    /// The "!" on Urgent's square.
    static var urgentMark: Text { Text("!").font(.system(size: 10, weight: .heavy, design: .rounded)) }
    #if os(macOS)
    /// The same for Core Graphics, drawn centred on the square.
    @MainActor
    static func drawUrgentMark(on square: CGRect) {
        let font = NSFont.systemFont(ofSize: 10, weight: .heavy)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 10) } ?? font
        let mark = NSAttributedString(string: "!", attributes: [.font: rounded, .foregroundColor: NSColor(Theme.onColor)])
        let size = mark.size()
        mark.draw(at: NSPoint(x: square.midX - size.width / 2, y: square.midY - size.height / 2))
    }
    #endif
}

// MARK: - Sub-issues

extension Marks {
    /// The sub-issue mark in a square: a hook from the top down and round to the right, into a small ring.
    static func subIssue(in rect: CGRect) -> [Shape] {
        let s = rect.width / 12
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var hook = Path()
        hook.move(to: point(2.5, 2))
        hook.addLine(to: point(2.5, 6))
        hook.addQuadCurve(to: point(4.5, 8), control: point(2.5, 8))
        hook.addLine(to: point(6.6, 8))
        let line = 1.3 * s
        return [
            Shape(path: hook, stroke: StrokeStyle(lineWidth: line, lineCap: .round)),
            Shape(path: Path(ellipseIn: CGRect(origin: point(6.8, 6.3), size: CGSize(width: 3.4 * s, height: 3.4 * s))), stroke: StrokeStyle(lineWidth: line)),
        ]
    }
}

// MARK: - Folding

extension Marks {
    /// The arrow that folds the sub-issues under an issue in or out: to the right while they are folded in, down while
    /// they show.
    static func foldArrow(folded: Bool, center: CGPoint) -> [Shape] {
        var path = Path()
        if folded {
            path.move(to: CGPoint(x: center.x - 1.5, y: center.y - 3.5))
            path.addLine(to: CGPoint(x: center.x + 2, y: center.y))
            path.addLine(to: CGPoint(x: center.x - 1.5, y: center.y + 3.5))
        } else {
            path.move(to: CGPoint(x: center.x - 3.5, y: center.y - 1.5))
            path.addLine(to: CGPoint(x: center.x, y: center.y + 2))
            path.addLine(to: CGPoint(x: center.x + 3.5, y: center.y - 1.5))
        }
        return [Shape(path: path, stroke: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))]
    }
}

// MARK: - Milestones

extension Marks {
    /// A milestone's diamond in a square: an outline, dashed for "No milestone"; filled when completed; with a small
    /// diamond inside for the one being worked towards, also when it is late.
    /// `dashed` draws the outline dashed whatever the mark, as for a stretch of the roadmap without a date.
    static func milestone(_ mark: MilestoneMark, in rect: CGRect, dashed: Bool = false) -> [Shape] {
        let outline = PlanningGlyph.diamond(in: rect, inset: rect.width * 0.114)
        let line = StrokeStyle(lineWidth: max(1.2, 1.5 * rect.width / 14), lineJoin: .round, dash: mark == .none || dashed ? [2, 2] : [])
        switch mark {
        case .completed:
            return [Shape(path: outline)]
        case .current, .late:
            return [Shape(path: outline, stroke: line), Shape(path: PlanningGlyph.diamond(in: rect, inset: rect.width * 0.34))]
        case .upcoming, .none:
            return [Shape(path: outline, stroke: line)]
        }
    }
}

// MARK: - Status

extension Marks {
    /// A status's circle in a square: dashed for the backlog, empty to start, filling up as work goes on, and filled
    /// with a check when done or a cross when canceled; a ring with a plus for an issue on none of your boards.
    static func status(_ glyph: StatusGlyph, in frame: CGRect) -> [Shape] {
        let rect = frame.insetBy(dx: 1.25, dy: 1.25)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let ring = Path(ellipseIn: rect)
        let s = frame.width / 14
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: frame.minX + x * s, y: frame.minY + y * s) }
        if glyph.addsToProject {
            var plus = Path()
            plus.move(to: point(7, 4.6))
            plus.addLine(to: point(7, 9.4))
            plus.move(to: point(4.6, 7))
            plus.addLine(to: point(9.4, 7))
            return [
                Shape(path: ring, stroke: StrokeStyle(lineWidth: 1.5)),
                Shape(path: plus, stroke: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round)),
            ]
        }
        switch glyph.category {
        case .backlog:
            return [Shape(path: ring, stroke: StrokeStyle(lineWidth: 1.5, dash: [2, 2.3]))]
        case .unstarted:
            return [Shape(path: ring, stroke: StrokeStyle(lineWidth: 1.5))]
        case .started:
            var pie = Path()
            pie.move(to: center)
            // Clockwise from twelve o'clock, in coordinates that run down the screen.
            pie.addArc(
                center: center, radius: rect.width / 2 - 2.5,
                startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * glyph.progress), clockwise: false
            )
            pie.closeSubpath()
            return [Shape(path: ring, stroke: StrokeStyle(lineWidth: 1.5)), Shape(path: pie)]
        case .completed:
            var check = Path()
            check.move(to: point(4.4, 7.2))
            check.addLine(to: point(6.2, 9))
            check.addLine(to: point(9.6, 5.2))
            return [
                Shape(path: Path(ellipseIn: rect.insetBy(dx: -0.75, dy: -0.75))),
                Shape(path: check, ink: .onColor, stroke: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round, lineJoin: .round)),
            ]
        case .canceled:
            var cross = Path()
            cross.move(to: point(4.8, 4.8))
            cross.addLine(to: point(9.2, 9.2))
            cross.move(to: point(9.2, 4.8))
            cross.addLine(to: point(4.8, 9.2))
            return [
                Shape(path: Path(ellipseIn: rect.insetBy(dx: -0.75, dy: -0.75))),
                Shape(path: cross, ink: .onColor, stroke: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round)),
            ]
        }
    }
}

// MARK: - Picking

extension Marks {
    /// The box that picks a row, 14 points: an outline, or filled with a tick once picked. The box takes the mark's
    /// colour and the tick the second one: on the accent of a picked row of the list, a white box with an accent tick;
    /// in a picker's row, an accent box with a white tick.
    static func checkbox(checked: Bool, in box: CGRect) -> [Shape] {
        guard checked else {
            return [Shape(path: Path(roundedRect: box.insetBy(dx: 0.6, dy: 0.6), cornerRadius: 4, style: .continuous), ink: .off, stroke: StrokeStyle(lineWidth: 1.2))]
        }
        var tick = Path()
        tick.move(to: CGPoint(x: box.minX + 3.6, y: box.midY + 0.2))
        tick.addLine(to: CGPoint(x: box.minX + 6, y: box.midY + 2.6))
        tick.addLine(to: CGPoint(x: box.maxX - 3.4, y: box.midY - 2.6))
        return [
            Shape(path: Path(roundedRect: box, cornerRadius: 4, style: .continuous)),
            Shape(path: tick, ink: .onColor, stroke: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)),
        ]
    }
}
