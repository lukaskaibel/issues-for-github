import SwiftUI

/// Draws a status glyph into any graphics context. Used by the icon view and the painted rows.
enum StatusPainter {
    static func draw(_ glyph: StatusGlyph, in frame: CGRect, context: GraphicsContext) {
        context.draw(Marks.status(glyph, in: frame), mark: glyph.color)
    }
}
