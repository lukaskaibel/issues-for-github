#if os(macOS)
import AppKit
import SwiftUI

/// What a row of the list lifts off as when it is dragged: the board's lifted card, with the row on it. It is drawn
/// from the views the board's drag shows, so that it is the same card: its colour and corners, no border, the deep
/// shadow of a lifted card (`liftedShadow`), the edge of a second card under it when it carries others along, how
/// many on its corner (`PickedCount`), an epic's issues as `EpicGroupCard`, and over an issue it would go under, the
/// smaller card with "Sub-issue of" under it (`NestHint`). A row as wide as the list doesn't tilt as a card does.
@MainActor
enum LiftedImage {
    /// Room around the card for its shadow and the count on its corner.
    static let margin = NSEdgeInsets(top: 16, left: 28, bottom: 44, right: 28)
    /// Over an issue it would go under, the card shows the start of the row, no wider than this.
    static let nestingWidth: CGFloat = 380

    /// A row as its card: `content` is the row's own picture, as wide as the row; the card covers it but for `inset` at
    /// either end and a point at the top and bottom, as the row lights up. Returns where the image's top left corner
    /// is from the row's.
    static func row(_ content: NSImage, inset: CGFloat, count: Int?, appearance: NSAppearance) -> (image: NSImage, origin: NSPoint)? {
        let card = RowCard(content: content, inset: inset, width: content.size.width - 2 * inset)
            .background(alignment: .top) { if count != nil { CardStackEdge() } }
            .overlay(alignment: .topTrailing) { if let count { PickedCount(count: count) } }
            .liftedShadow()
        return render(card, appearance: appearance).map { ($0, NSPoint(x: inset - margin.left, y: 1 - margin.top)) }
    }

    /// The header over an epic's issues as the card they lift off as together, as on the board.
    static func group(_ group: Nesting.EpicGroup, rowWidth: CGFloat, inset: CGFloat, appearance: NSAppearance) -> (image: NSImage, origin: NSPoint)? {
        let card = EpicGroupCard(group: group, width: rowWidth - 2 * inset).liftedShadow()
        return render(card, appearance: appearance).map { ($0, NSPoint(x: inset - margin.left, y: -margin.top)) }
    }

    /// Over an issue it would go under: the start of the row's card, with "Sub-issue of #n" under it, as the board's
    /// lifted card says it. Returns where the image's top left corner is from the card's.
    static func nesting(_ content: NSImage, inset: CGFloat, under parent: Item, count: Int?, appearance: NSAppearance) -> (image: NSImage, origin: NSPoint)? {
        let card = RowCard(content: content, inset: inset, width: min(content.size.width - 2 * inset, nestingWidth), fades: true)
            .background(alignment: .top) { if count != nil { CardStackEdge() } }
            .overlay(alignment: .topTrailing) { if let count { PickedCount(count: count) } }
            .overlay(alignment: .bottomLeading) { NestHint(parent: parent).offset(x: 10, y: 13) }
            .liftedShadow()
        return render(card, appearance: appearance).map { ($0, NSPoint(x: -margin.left, y: -margin.top)) }
    }

    /// The card with the row's picture on it, cut to the card's corners. A card narrower than the row fades its end
    /// out instead of cutting the title off.
    private struct RowCard: View {
        var content: NSImage
        var inset: CGFloat
        var width: CGFloat
        var fades = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous)
            Image(nsImage: content)
                .frame(width: content.size.width, height: content.size.height)
                .offset(x: -inset, y: -1)
                .frame(width: width, height: content.size.height - 2, alignment: .topLeading)
                .overlay(alignment: .trailing) {
                    if fades {
                        LinearGradient(colors: [Theme.cardLifted.opacity(0), Theme.cardLifted], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 56)
                    }
                }
                .background(shape.fill(Theme.cardLifted))
                .clipShape(shape)
        }
    }

    /// Draws a view in the list's appearance at the screen's scale, with room around it for its shadow.
    private static func render(_ view: some View, appearance: NSAppearance) -> NSImage? {
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let padded = view
            .padding(EdgeInsets(top: margin.top, leading: margin.left, bottom: margin.bottom, trailing: margin.right))
            .environment(\.colorScheme, dark ? .dark : .light)
        var image: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: padded)
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
            image = renderer.nsImage
        }
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }
}
#endif
