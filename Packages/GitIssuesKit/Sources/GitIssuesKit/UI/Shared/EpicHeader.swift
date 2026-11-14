import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The header over the issues of an epic standing together in a list's section or a board's column, one look on Mac,
/// iPhone and iPad: the epic's icon where the line down to its issues starts, its name, how many of its issues are
/// there, and at the end of the line the arrow that folds them away, shown always, as every fold arrow is. It stands a
/// little closer to its issues than to what is above it. Under the pointer it lights up in the rounded shape a row of
/// the list does.
///
/// `EpicHeader` draws it in SwiftUI, for the Mac's board and for iPhone and iPad; the Mac's list paints the same
/// header itself (`EpicHeaderRowCell`) from these measures and the same marks.
enum EpicHeaderLook {
    #if os(macOS)
    static let iconSize: CGFloat = 14
    /// The height of a line of the name, which the icon and the arrow are centred on.
    static let line: CGFloat = 16
    static let top: CGFloat = 8
    static let bottom: CGFloat = 4
    /// The square the arrow lights up in under the pointer, as a card's fold arrow does.
    static let arrowBox: CGFloat = 18
    static let nameFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let countFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    #else
    static let iconSize: CGFloat = 16
    static let line: CGFloat = 20
    static let top: CGFloat = 10
    static let bottom: CGFloat = 6
    static let arrowBox: CGFloat = 20
    #endif
    /// From the icon's column to the name.
    static let spacing: CGFloat = 8
    /// Between the name and the count, which keeps to the name's last word: a figure space, which doesn't break.
    static let countGap = "\u{2007}"
    /// The least room between the count and the arrow.
    static let arrowGap: CGFloat = 8
    static let highlightRadius: CGFloat = 8
}

struct EpicHeader: View {
    var group: Nesting.EpicGroup
    /// Where the column the line down to the epic's issues runs in starts, and how wide it is; the icon stands in its
    /// middle. In a list that is the issues' status column, on a board the gutter sub-issue cards hang in.
    var iconColumn: (x: CGFloat, width: CGFloat)
    /// From the arrow's square to the header's trailing edge.
    var trailing: CGFloat
    var lineLimit: Int
    /// Under the pointer, or pressed.
    var highlighted = false
    var hoveringFold = false

    #if os(iOS)
    // The same measures, growing with the reader's text size.
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = EpicHeaderLook.iconSize
    @ScaledMetric(relativeTo: .subheadline) private var line: CGFloat = EpicHeaderLook.line
    @ScaledMetric(relativeTo: .subheadline) private var arrowScale: CGFloat = 1.2
    private var nameFont: Font { .subheadline.weight(.semibold) }
    private var countFont: Font { .subheadline }
    #else
    private var iconSize: CGFloat { EpicHeaderLook.iconSize }
    private var line: CGFloat { EpicHeaderLook.line }
    private var arrowScale: CGFloat { 1 }
    private var nameFont: Font { Font(EpicHeaderLook.nameFont as CTFont) }
    private var countFont: Font { Font(EpicHeaderLook.countFont as CTFont) }
    #endif

    var body: some View {
        let name = Text(group.epic.title).font(nameFont).foregroundStyle(Theme.text)
        let count = Text(verbatim: "\(group.count)").font(countFont).monospacedDigit().foregroundStyle(Theme.textTertiary)
        HStack(alignment: .top, spacing: 0) {
            // The count follows the name's last word, on whichever line that ends.
            Text("\(name)\(EpicHeaderLook.countGap)\(count)")
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: line)
            Spacer(minLength: EpicHeaderLook.arrowGap)
            // The arrow's place; the Canvas behind draws it.
            Color.clear.frame(width: EpicHeaderLook.arrowBox, height: line)
        }
        .padding(.leading, iconColumn.x + iconColumn.width + EpicHeaderLook.spacing)
        .padding(.trailing, trailing)
        .padding(.top, EpicHeaderLook.top)
        .padding(.bottom, EpicHeaderLook.bottom)
        .background {
            // The icon, the start of the line down to the issues, and the arrow, in one pass.
            Canvas { context, size in
                let midY = EpicHeaderLook.top + line / 2
                let icon = CGRect(x: iconColumn.x + (iconColumn.width - iconSize) / 2, y: midY - iconSize / 2, width: iconSize, height: iconSize)
                if !group.folded {
                    // On a whole device pixel, as a rectangle view is drawn.
                    let scale = context.environment.displayScale
                    let x = ((iconColumn.x + iconColumn.width / 2 - 0.5) * scale).rounded() / scale
                    context.fill(Path(CGRect(x: x, y: icon.maxY + 3, width: 1, height: max(0, size.height - icon.maxY - 3))), with: .color(Theme.treeLine))
                }
                context.draw(Marks.epic(in: icon), mark: Theme.epic)
                let arrow = CGRect(x: size.width - trailing - EpicHeaderLook.arrowBox, y: midY - EpicHeaderLook.arrowBox / 2, width: EpicHeaderLook.arrowBox, height: EpicHeaderLook.arrowBox)
                if hoveringFold {
                    context.fill(Path(roundedRect: arrow, cornerRadius: 5, style: .continuous), with: .color(Theme.partHover))
                }
                context.draw(
                    Marks.foldArrow(folded: group.folded, center: CGPoint(x: arrow.midX, y: arrow.midY), scale: arrowScale),
                    mark: hoveringFold ? Theme.textSecondary : Theme.textTertiary
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: EpicHeaderLook.highlightRadius, style: .continuous)
                .fill(highlighted ? Theme.selected : .clear)
        )
    }
}

#if os(macOS)
extension EpicHeader {
    /// How tall a header is at this width, from how many lines its name takes beside the count and the arrow: what a
    /// board places its rows with before the header has been drawn.
    static func height(of group: Nesting.EpicGroup, width: CGFloat, iconColumn: (x: CGFloat, width: CGFloat), trailing: CGFloat, lineLimit: Int) -> CGFloat {
        let look = EpicHeaderLook.self
        let name = width - (iconColumn.x + iconColumn.width + look.spacing) - look.arrowGap - look.arrowBox - trailing
        let lines = MeasuredHeights.lines(of: group.epic.title + look.countGap + "\(group.count)", font: look.nameFont, width: name, limit: lineLimit)
        return max(look.line, MeasuredHeights.textHeight(lines: lines, font: look.nameFont)) + look.top + look.bottom
    }

    /// Where the arrow is in a header with this frame, for clicks: its square, centred on the first line.
    static func foldFrame(in frame: CGRect, trailing: CGFloat) -> CGRect {
        let look = EpicHeaderLook.self
        return CGRect(
            x: frame.maxX - trailing - look.arrowBox, y: frame.minY + look.top + (look.line - look.arrowBox) / 2,
            width: look.arrowBox, height: look.arrowBox
        )
    }
}
#endif
