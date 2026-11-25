import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The header over issues standing together in a list's section or a board's column, one look on Mac, iPhone and
/// iPad: an icon where the line down to its issues starts, a name, how many of its issues are there, and at the end of
/// the line the arrow that folds them away, shown always, as every fold arrow is. It stands a little closer to its
/// issues than to what is above it. Under the pointer it lights up in the rounded shape a row of the list does.
///
/// Over an epic's issues it has the epic's icon and name. Over sub-issues of a parent that stands elsewhere it is
/// quieter, as that parent isn't one of the cards there, and reads like the parent itself would: no icon, the parent's
/// name in grey where the issues beside it start (their first mark in a list, their text on a board), and under it,
/// smaller, the parent's number and its status ("#9 · In Review"); the line down to the sub-issues starts right under
/// it, as from a parent issue. Inside an epic's group it hangs one level in, with the epic's line beside it, as an
/// issue there does.
///
/// `GroupHeader` draws it in SwiftUI, for the Mac's board and for iPhone and iPad; the Mac's list paints its header
/// itself (`GroupHeaderRowCell`) with the same marks and fonts, as a row of the list, centred in the row's height.
enum GroupHeaderLook {
    #if os(macOS)
    static let iconSize: CGFloat = 14
    /// The height of a line of the name, which the icon and the arrow are centred on.
    static let line: CGFloat = 16
    static let top: CGFloat = 8
    static let bottom: CGFloat = 4
    /// The square the arrow lights up in under the pointer, as a card's fold arrow does.
    static let arrowBox: CGFloat = 18
    static let nameFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    /// A parent's name, quieter than an epic's.
    static let parentNameFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let countFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    /// The line under a parent's name: its number and its status.
    static let detailFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let detailLine: CGFloat = 14
    #else
    static let iconSize: CGFloat = 16
    static let line: CGFloat = 20
    static let top: CGFloat = 10
    static let bottom: CGFloat = 6
    static let arrowBox: CGFloat = 20
    static let detailLine: CGFloat = 16
    #endif
    /// From the icon's column to the name.
    static let spacing: CGFloat = 8
    /// Between the name and the count, which keeps to the name's last word: a figure space, which doesn't break.
    static let countGap = "\u{2007}"
    /// The least room between the count and the arrow.
    static let arrowGap: CGFloat = 8
    static let highlightRadius: CGFloat = 8
    /// From the name to the line under it.
    static let detailGap: CGFloat = 1
    /// From the bottom of a parent's name, or the line under it, to the start of the line down to its sub-issues.
    static let lineGap: CGFloat = 2
    /// The symbol of a parent, as sub-issues name theirs, in menus.
    static let parentSymbol = "arrow.turn.left.up"
}

struct GroupHeader: View {
    var group: Nesting.Group
    /// Under a parent's name: its number and its status, "#9 · In Review".
    var detail: String? = nil
    /// Where it hangs inside an epic's group: one level in, with the epic's line beside it.
    var place = Nesting.Place()
    /// Where the column the line down to the group's issues runs in starts, and how wide it is; an epic's icon stands
    /// in its middle. In a list that is the issues' status column, on a board the gutter sub-issue cards hang in.
    var iconColumn: (x: CGFloat, width: CGFloat)
    /// How far into that column a parent's name starts, to stand where the issues beside it start: 0 in a list, where
    /// that is their first mark, the cards' padding on a board, where it is their text.
    var nameInset: CGFloat = 0
    /// How much further in each level hangs, down to a few levels, as the issues under it do.
    var indent: (step: CGFloat, deepest: Int) = (CardTreeLines.indent, CardTreeLines.deepest)
    /// The room above it to the row before, which the epic's line beside a header inside the epic's group bridges, as
    /// a card's lines do.
    var gap: CGFloat = 0
    /// From the arrow's square to the header's trailing edge.
    var trailing: CGFloat
    var lineLimit: Int
    /// Under the pointer, or pressed.
    var highlighted = false
    var hoveringFold = false
    /// The pointer on the line under a parent's name, which changes the parent's status: lit up as a card's parts are.
    var hoveringDetail = false

    #if os(iOS)
    // The same measures, growing with the reader's text size.
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = GroupHeaderLook.iconSize
    @ScaledMetric(relativeTo: .subheadline) private var line: CGFloat = GroupHeaderLook.line
    @ScaledMetric(relativeTo: .subheadline) private var arrowScale: CGFloat = 1.2
    private var nameFont: Font { .subheadline.weight(.semibold) }
    private var parentNameFont: Font { .subheadline.weight(.medium) }
    private var countFont: Font { .subheadline }
    private var detailFont: Font { .caption }
    #else
    private var iconSize: CGFloat { GroupHeaderLook.iconSize }
    private var line: CGFloat { GroupHeaderLook.line }
    private var arrowScale: CGFloat { 1 }
    private var nameFont: Font { Font(GroupHeaderLook.nameFont as CTFont) }
    private var parentNameFont: Font { Font(GroupHeaderLook.parentNameFont as CTFont) }
    private var countFont: Font { Font(GroupHeaderLook.countFont as CTFont) }
    private var detailFont: Font { Font(GroupHeaderLook.detailFont as CTFont) }
    #endif

    /// Where the icon's column is at the header's depth.
    private var column: (x: CGFloat, width: CGFloat) {
        (iconColumn.x + CGFloat(min(place.depth, indent.deepest)) * indent.step, iconColumn.width)
    }

    var body: some View {
        let parent = group.kind == .parent
        let name = Text(group.head.title)
            .font(parent ? parentNameFont : nameFont)
            .foregroundStyle(parent ? Theme.textSecondary : Theme.text)
        let count = Text(verbatim: "\(group.count)").font(countFont).monospacedDigit().foregroundStyle(Theme.textTertiary)
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: GroupHeaderLook.detailGap) {
                // The count follows the name's last word, on whichever line that ends.
                Text("\(name)\(GroupHeaderLook.countGap)\(count)")
                    .lineLimit(lineLimit)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: line)
                if let detail {
                    Text(verbatim: detail)
                        .font(detailFont)
                        .foregroundStyle(hoveringDetail ? Theme.textSecondary : Theme.textTertiary)
                        .lineLimit(1)
                        .frame(minHeight: GroupHeaderLook.detailLine)
                        .background {
                            if hoveringDetail {
                                Capsule().fill(Theme.partHover).padding(.horizontal, -5)
                            }
                        }
                }
            }
            Spacer(minLength: GroupHeaderLook.arrowGap)
            // The arrow's place; the Canvas behind draws it.
            Color.clear.frame(width: GroupHeaderLook.arrowBox, height: line)
        }
        .padding(.leading, parent ? column.x + nameInset : column.x + column.width + GroupHeaderLook.spacing)
        .padding(.trailing, trailing)
        .padding(.top, GroupHeaderLook.top)
        .padding(.bottom, GroupHeaderLook.bottom)
        .background {
            // The icon, the lines beside it and down to the issues, and the arrow, in one pass.
            Canvas { context, size in
                let column = column
                let midY = GroupHeaderLook.top + line / 2
                let icon = CGRect(x: column.x + (column.width - iconSize) / 2, y: midY - iconSize / 2, width: iconSize, height: iconSize)
                // On a whole device pixel, as a rectangle view is drawn.
                let scale = context.environment.displayScale
                func pixel(_ x: CGFloat) -> CGFloat { ((x - 0.5) * scale).rounded() / scale }
                if !group.folded {
                    // From under the epic's icon, or from under a parent's name and the line below it, as from a parent
                    // issue.
                    let x = pixel(column.x + column.width / 2)
                    let top = parent ? size.height - GroupHeaderLook.bottom + GroupHeaderLook.lineGap : icon.maxY + 3
                    context.fill(Path(CGRect(x: x, y: top, width: 1, height: max(0, size.height - top))), with: .color(Theme.treeLine))
                }
                if !parent {
                    context.draw(Marks.epic(in: icon), mark: Theme.epic)
                }
                let arrow = CGRect(x: size.width - trailing - GroupHeaderLook.arrowBox, y: midY - GroupHeaderLook.arrowBox / 2, width: GroupHeaderLook.arrowBox, height: GroupHeaderLook.arrowBox)
                if hoveringFold {
                    context.fill(Path(roundedRect: arrow, cornerRadius: 5, style: .continuous), with: .color(Theme.partHover))
                }
                context.draw(
                    Marks.foldArrow(folded: group.folded, center: CGPoint(x: arrow.midX, y: arrow.midY), scale: arrowScale),
                    mark: hoveringFold ? Theme.textSecondary : Theme.textTertiary
                )
            }
        }
        .background(alignment: .top) {
            // Inside an epic's group, the epic's line beside it, from the row above.
            if place.depth > 0 {
                Canvas { context, size in
                    let scale = context.environment.displayScale
                    func pixel(_ x: CGFloat) -> CGFloat { ((x - 0.5) * scale).rounded() / scale + 0.5 }
                    let column = column
                    // To the epic's icon, or to a parent's name.
                    let branchEnd = parent ? column.x + nameInset - 3 : column.x + (column.width - iconSize) / 2 - 3
                    let lines = Marks.treeLines(
                        place, deepest: indent.deepest, lineX: { pixel(iconColumn.x + CGFloat($0) * indent.step + iconColumn.width / 2) },
                        branchY: gap + GroupHeaderLook.top + line / 2, branchEnd: branchEnd, height: size.height
                    )
                    context.stroke(lines, with: .color(Theme.treeLine), lineWidth: 1)
                }
                .padding(.top, -gap)
                .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: GroupHeaderLook.highlightRadius, style: .continuous)
                .fill(highlighted ? Theme.selected : .clear)
                .padding(.leading, CGFloat(min(place.depth, indent.deepest)) * indent.step)
        )
    }
}

extension Nesting.Group {
    /// The menu entry and VoiceOver action that folds the group's issues away or shows them again.
    var foldAction: LocalizedStringResource {
        switch kind {
        case .epic: folded ? .showEpicIssues : .foldEpicIssues
        case .parent: folded ? .unfoldSubIssuesMenuItem : .foldSubIssuesMenuItem
        }
    }

    /// What the arrow says, as a tooltip and to VoiceOver.
    var foldLabel: String {
        switch kind {
        case .epic: String(localized: folded ? .unfoldEpicGroupTooltip(count: count) : .foldEpicGroupTooltip)
        case .parent: String(localized: folded ? .unfoldSubIssuesTooltip(count: count) : .foldSubIssuesTooltip)
        }
    }

    /// What VoiceOver reads for the header: whose issues they are, how many, and for a parent where it is (`detail`).
    func spoken(detail: String?) -> String {
        switch kind {
        case .epic:
            return String(localized: .epicGroupSpoken(epic: head.title, count: count))
        case .parent:
            let spoken = String(localized: .parentGroupSpoken(count: count, parent: head.title))
            return detail.map { "\(spoken), \($0)" } ?? spoken
        }
    }
}

#if os(macOS)
extension GroupHeader {
    /// How tall a header is at this width, from how many lines its name takes beside the count and the arrow, and the
    /// line under a parent's name: what a board places its rows with before the header has been drawn.
    static func height(
        of group: Nesting.Group, detail: String?, place: Nesting.Place, width: CGFloat, iconColumn: (x: CGFloat, width: CGFloat),
        nameInset: CGFloat = 0, trailing: CGFloat, lineLimit: Int
    ) -> CGFloat {
        let look = GroupHeaderLook.self
        let font = group.kind == .parent ? look.parentNameFont : look.nameFont
        let name = width - nameX(of: group.kind, place: place, iconColumn: iconColumn, nameInset: nameInset) - look.arrowGap - look.arrowBox - trailing
        let lines = MeasuredHeights.lines(of: group.head.title + look.countGap + "\(group.count)", font: font, width: name, limit: lineLimit)
        let detailHeight = detail == nil ? 0 : look.detailGap + look.detailLine
        return max(look.line, MeasuredHeights.textHeight(lines: lines, font: font)) + detailHeight + look.top + look.bottom
    }

    /// Where the name starts, at the header's depth: after an epic's icon, or for a parent where the issues beside it
    /// start.
    static func nameX(of kind: Nesting.Group.Kind, place: Nesting.Place, iconColumn: (x: CGFloat, width: CGFloat), nameInset: CGFloat) -> CGFloat {
        let column = iconColumn.x + CGFloat(min(place.depth, CardTreeLines.deepest)) * CardTreeLines.indent
        return kind == .parent ? column + nameInset : column + iconColumn.width + GroupHeaderLook.spacing
    }

    /// Where the arrow is in a header with this frame, for clicks: its square, centred on the first line.
    static func foldFrame(in frame: CGRect, trailing: CGFloat) -> CGRect {
        let look = GroupHeaderLook.self
        return CGRect(
            x: frame.maxX - trailing - look.arrowBox, y: frame.minY + look.top + (look.line - look.arrowBox) / 2,
            width: look.arrowBox, height: look.arrowBox
        )
    }

    /// Where the line under a parent's name is in a header with this frame, for clicks: as wide as its text, with a
    /// little room around it.
    static func detailFrame(
        _ detail: String, in frame: CGRect, place: Nesting.Place, iconColumn: (x: CGFloat, width: CGFloat), nameInset: CGFloat
    ) -> CGRect {
        let look = GroupHeaderLook.self
        let width = MeasuredHeights.width(of: detail, font: look.detailFont)
        return CGRect(
            x: frame.minX + nameX(of: .parent, place: place, iconColumn: iconColumn, nameInset: nameInset) - 5,
            y: frame.maxY - look.bottom - look.detailLine,
            width: width + 10, height: look.detailLine
        )
    }
}
#endif
