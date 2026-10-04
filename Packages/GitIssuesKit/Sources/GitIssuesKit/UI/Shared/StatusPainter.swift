import SwiftUI

/// Draws a status glyph into any graphics context. Used by the icon view and the painted rows.
enum StatusPainter {
    static func draw(_ glyph: StatusGlyph, in frame: CGRect, context: GraphicsContext) {
        let rect = frame.insetBy(dx: 1.25, dy: 1.25)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let ring = Path(ellipseIn: rect)
        let s = frame.width / 14
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: frame.minX + x * s, y: frame.minY + y * s) }
        switch glyph.category {
        case .backlog:
            context.stroke(ring, with: .color(glyph.color), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2.3]))
        case .unstarted:
            context.stroke(ring, with: .color(glyph.color), lineWidth: 1.5)
        case .started:
            context.stroke(ring, with: .color(glyph.color), lineWidth: 1.5)
            var pie = Path()
            pie.move(to: center)
            pie.addArc(
                center: center, radius: rect.width / 2 - 2.5,
                startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * glyph.progress), clockwise: false
            )
            pie.closeSubpath()
            context.fill(pie, with: .color(glyph.color))
        case .completed:
            context.fill(Path(ellipseIn: rect.insetBy(dx: -0.75, dy: -0.75)), with: .color(glyph.color))
            var check = Path()
            check.move(to: point(4.4, 7.2))
            check.addLine(to: point(6.2, 9))
            check.addLine(to: point(9.6, 5.2))
            context.stroke(check, with: .color(Theme.onColor), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round, lineJoin: .round))
        case .canceled:
            context.fill(Path(ellipseIn: rect.insetBy(dx: -0.75, dy: -0.75)), with: .color(glyph.color))
            var cross = Path()
            cross.move(to: point(4.8, 4.8))
            cross.addLine(to: point(9.2, 9.2))
            cross.move(to: point(9.2, 4.8))
            cross.addLine(to: point(4.8, 9.2))
            context.stroke(cross, with: .color(Theme.onColor), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
        }
    }
}
