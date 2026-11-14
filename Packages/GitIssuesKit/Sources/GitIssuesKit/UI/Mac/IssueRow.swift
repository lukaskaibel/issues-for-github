#if os(macOS)
import AppKit
import SwiftUI

/// What one list row shows, gathered up front so drawing needs no lookups.
struct IssueRowModel: Equatable {
    var item: Item
    var glyph: StatusGlyph
    var priority: PriorityLevel
    /// Whether the project has the field, so the icon can be clicked to change it.
    var showsPriority = true
    var showsStatus = true
    /// Shown in "My Issues", where rows come from several projects.
    var projectTitle: String?
    var due: DueBadge?
    /// What blocks it, when an open issue does.
    var blocker: BlockerMark?
    /// Picked for a change to several issues at once, and whether anything is picked, which shows every
    /// row's checkbox.
    var selected = false
    var selecting = false
    /// How the row hangs under a parent in its group.
    var nest = Nesting.Place()
    /// How many sub-issues hang under this one in its group, folded or not; nil when none do.
    var nested: Int?
    var folded = false
    /// A sub-issue whose parent is in another group names the parent.
    var showsParent = false
    /// Whether that parent is an epic, which it then names with the epic's icon.
    var parentIsEpic = false
    /// The milestone it is planned for, where the list isn't a milestone's.
    var milestone: String?
    var milestoneMark: MilestoneMark = .upcoming
    /// The project's own fields the view shows, such as an iteration or a "Workstream".
    var chips: [FieldChip] = []
}

/// One issue, drawn directly. Configuring and drawing a recycled cell takes a fraction of a millisecond.
final class IssueRowCell: NSView, NSViewToolTipOwner {
    weak var model: AppModel?
    /// What the row shows now.
    private(set) var row: IssueRowModel?
    /// The date's place, for its tooltip.
    private var dateRect = NSRect.zero
    /// The number's place, whose tooltip names the repository.
    private var numberRect = NSRect.zero
    private var highlighted = false
    private var number = NSAttributedString()
    private var title = NSAttributedString()
    private var date = NSAttributedString()
    private var project: NSAttributedString?
    private var subCount: NSAttributedString?
    private var blockerText: NSAttributedString?
    private var parentHint: NSAttributedString?
    private var milestoneText: NSAttributedString?
    private var milestoneSize = NSSize.zero
    private var dueText: NSAttributedString?
    private var dueIcon: NSImage?
    private var labels: [(text: NSAttributedString, size: NSSize, color: NSColor)] = []
    // Measured once when the row is configured; measuring text on every draw is what makes drawing slow.
    private var numberSize = NSSize.zero
    private var titleSize = NSSize.zero
    private var dateSize = NSSize.zero
    private var projectSize = NSSize.zero
    private var subCountSize = NSSize.zero
    private var blockerSize = NSSize.zero
    private var parentHintSize = NSSize.zero
    private var dueSize = NSSize.zero
    /// Where the clickable parts were drawn last, in this cell's coordinates.
    private(set) var parts: [(kind: PickerKind, rect: NSRect)] = []
    /// The part under the pointer, which gets a soft highlight like a button.
    var hoveredPart: PickerKind? {
        didSet { if hoveredPart != oldValue { needsDisplay = true } }
    }

    func part(at point: NSPoint) -> (kind: PickerKind, rect: NSRect)? {
        parts.first { $0.rect.insetBy(dx: -3, dy: -4).contains(point) }
    }

    /// The arrow that folds the sub-issues hanging under this issue in or out, where it was drawn last.
    private(set) var foldRect: NSRect?
    var hoveringFold = false {
        didSet { if hoveringFold != oldValue { needsDisplay = true } }
    }

    func isOnFold(_ point: NSPoint) -> Bool {
        foldRect?.insetBy(dx: -3, dy: -4).contains(point) ?? false
    }

    /// Sub-issues hang this much further in per level, down to a few levels.
    static let indent: CGFloat = 20
    static let deepestIndent = 5
    /// Off while the row is drawn as a card being dragged.
    private var drawsTree = true

    /// The start of the row, where the checkbox shows: a click there picks the issue.
    var checkboxRect: NSRect {
        NSRect(x: IssueTable.inset, y: 0, width: 22, height: bounds.height)
    }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    override func viewDidChangeEffectiveAppearance() {
        needsDisplay = true
    }

    func configure(_ row: IssueRowModel, highlighted: Bool) {
        if row != self.row {
            // A view taken over from another issue starts without that issue's pointer on its parts, nor the places
            // they had.
            if row.item.id != self.row?.item.id {
                hoveredPart = nil
                hoveringFold = false
                parts = []
                foldRect = nil
            }
            self.row = row
            let item = row.item
            // Picked rows are filled with the accent colour, as a Mac list shows its selection, and read in white.
            let onAccent = row.selected
            let primary = onAccent ? NSColor.white : NSColor(Theme.text)
            let secondary = onAccent ? NSColor.white.withAlphaComponent(0.88) : NSColor(Theme.textSecondary)
            let tertiary = onAccent ? NSColor.white.withAlphaComponent(0.8) : NSColor(Theme.textTertiary)
            let truncating = NSMutableParagraphStyle()
            truncating.lineBreakMode = .byTruncatingTail
            number = NSAttributedString(string: item.displayNumber, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: tertiary,
            ])
            title = NSAttributedString(string: item.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: primary,
                .paragraphStyle: truncating,
            ])
            date = NSAttributedString(string: relativeDate(item.updatedAt), attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: tertiary,
            ])
            project = row.projectTitle.map {
                NSAttributedString(string: $0, attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: tertiary,
                    .paragraphStyle: truncating,
                ])
            }
            parentHint = row.showsParent ? item.parentNumber.map { number in
                NSAttributedString(string: row.parentIsEpic ? item.parentTitle ?? "#\(number)" : "#\(number) \(item.parentTitle ?? "")", attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: tertiary,
                    .paragraphStyle: truncating,
                ])
            } : nil
            subCount = item.subTotal > 0
                ? NSAttributedString(string: "\(item.subCompleted)/\(item.subTotal)", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: secondary,
                ])
                : nil
            blockerText = row.blocker?.text.map {
                NSAttributedString(string: $0, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: onAccent ? NSColor.white : NSColor(Theme.blocked),
                ])
            }
            if let due = row.due {
                let color = onAccent ? NSColor.white : NSColor(due.tone.color)
                dueText = NSAttributedString(string: due.label, attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: color,
                ])
                dueIcon = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                        .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
            } else {
                dueText = nil
                dueIcon = nil
            }
            milestoneText = row.milestone.map {
                NSAttributedString(string: $0, attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: secondary,
                    .paragraphStyle: truncating,
                ])
            }
            milestoneSize = milestoneText?.size() ?? .zero
            // An epic's own label says what the row shows already.
            labels = item.labels.filter { !(item.isEpic && Item.isEpicLabel($0.name)) }.prefix(3).map { label in
                let text = NSAttributedString(string: label.name, attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: onAccent ? NSColor.white : NSColor(Theme.textBody),
                ])
                return (text, text.size(), NSColor(Theme.labelColor(label.color)))
            }
            numberSize = number.size()
            titleSize = title.size()
            dateSize = date.size()
            projectSize = project?.size() ?? .zero
            subCountSize = subCount?.size() ?? .zero
            blockerSize = blockerText?.size() ?? .zero
            parentHintSize = parentHint?.size() ?? .zero
            dueSize = dueText?.size() ?? .zero
            var spoken = row.due.map {
                String(localized: .issueRowSpokenWithDue(number: item.displayNumber, title: item.title, due: $0.tooltip))
            } ?? "\(item.displayNumber) \(item.title)"
            if row.blocker != nil, let blocked = model?.tooltip(.blockedBy, for: item) { spoken += ", \(blocked)" }
            setAccessibilityLabel(item.parentNumber.map { number in
                let parent = String(localized: row.parentIsEpic
                    ? .epicTooltip(epic: item.parentTitle ?? "#\(number)") : .subIssueOf(number: "#\(number)"))
                return "\(spoken), \(parent)"
            } ?? spoken)
            needsDisplay = true
        }
        if highlighted != self.highlighted {
            self.highlighted = highlighted
            needsDisplay = true
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    /// The row as a card lifted off the list, to drag around.
    func dragImage() -> NSImage? {
        guard let content = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        // Without the hover fill and checkbox, which belong to the pointer, not to the issue, nor the accent fill of a
        // picked row: lifted, it is a card like any other, as on the board.
        let wasHighlighted = highlighted, wasHovered = hoveredPart, wasRow = row
        if var lifted = row, lifted.selected || lifted.selecting {
            lifted.selected = false
            lifted.selecting = false
            configure(lifted, highlighted: false)
        }
        highlighted = false
        hoveredPart = nil
        drawsTree = false
        cacheDisplay(in: bounds, to: content)
        drawsTree = true
        if let wasRow { configure(wasRow, highlighted: wasHighlighted) }
        highlighted = wasHighlighted
        hoveredPart = wasHovered
        needsDisplay = true
        let appearance = effectiveAppearance
        return NSImage(size: bounds.size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                let card = NSBezierPath(
                    roundedRect: rect.insetBy(dx: IssueTable.inset, dy: 1).insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7
                )
                NSColor(Theme.cardLifted).setFill()
                card.fill()
                NSColor(Theme.cardLiftedBorder).setStroke()
                card.lineWidth = 1
                card.stroke()
            }
            // On top of the card; a plain `draw(in:)` would copy the transparent pixels over it.
            content.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let row, let context = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size
        let midY = size.height / 2

        let onAccent = row.selected
        if row.selected {
            NSColor(Theme.accentFill).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: IssueTable.inset, dy: 1), xRadius: 8, yRadius: 8).fill()
        } else if highlighted {
            NSColor(Theme.selected).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: IssueTable.inset, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        // The checkbox sits under the section headers' fold arrow; it shows on hover and while picking.
        if row.selected || row.selecting || highlighted {
            drawCheckbox(checked: row.selected, center: NSPoint(x: IssueTable.inset + 15, y: midY))
        }
        // Each part lights up in a shape that suits it, as in Linear: a small square behind an icon, a halo
        // around avatars, and chips in their own shape.
        let partHover = onAccent ? NSColor.white.withAlphaComponent(0.22) : NSColor(Theme.partHover)
        func iconHover(_ kind: PickerKind, _ rect: NSRect) {
            guard hoveredPart == kind else { return }
            partHover.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: -4, dy: -4), xRadius: 5, yRadius: 5).fill()
        }
        var parts: [(kind: PickerKind, rect: NSRect)] = []
        let canEditFields = row.item.kind != .draft

        // Left to right: priority, number, status. The priority lines up with the headers' status icon.
        var x: CGFloat = IssueTable.inset + 28
        if row.showsPriority {
            let rect = NSRect(x: x, y: midY - 7, width: 14, height: 14)
            parts.append((.priority, rect))
            iconHover(.priority, rect)
        }
        drawPriority(row.priority, x: x, midY: midY, onAccent: onAccent)
        x += 14 + 10
        number.draw(at: NSPoint(x: x, y: midY - numberSize.height / 2))
        let numberRect = NSRect(x: x, y: midY - 9, width: numberSize.width, height: 18)
        x += 40 + 10
        // A sub-issue hangs under its parent: status and title move in, with a line from the parent's status.
        if drawsTree { drawTree(row, from: x, midY: midY) }
        x += CGFloat(min(row.nest.depth, Self.deepestIndent)) * Self.indent
        if row.showsStatus {
            let rect = NSRect(x: x, y: midY - 7, width: 14, height: 14)
            parts.append((.status, rect))
            iconHover(.status, rect)
        }
        var glyph = row.glyph
        if onAccent, glyph.category != .completed, glyph.category != .canceled { glyph.color = .white }
        StatusPainter.draw(glyph, in: CGRect(x: x, y: midY - 7, width: 14, height: 14), cg: context)
        x += 14 + 10
        // The arrow that folds the sub-issues under this issue in or out.
        if row.nested != nil {
            let rect = NSRect(x: x - 4, y: midY - 7, width: 14, height: 14)
            foldRect = rect
            if hoveringFold {
                partHover.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 5, yRadius: 5).fill()
            }
            Self.drawFoldArrow(folded: row.folded, center: NSPoint(x: rect.midX, y: rect.midY), color: onAccent ? .white : NSColor(Theme.textSecondary))
            x = rect.maxX + 8
        } else {
            foldRect = nil
        }

        // Right to left: assignees, date, project, labels.
        var right = size.width - IssueTable.inset - 14
        var avatarRing = NSColor(row.selected ? Theme.accentFill : highlighted ? Theme.selected : Theme.panel)
        if canEditFields {
            let count = CGFloat(max(min(row.item.assignees.count, 3), 1))
            let width = 18 + (count - 1) * 13
            let rect = NSRect(x: right - width, y: midY - 9, width: width, height: 18)
            parts.append((.assignees, rect))
            if hoveredPart == .assignees {
                let halo = rect.insetBy(dx: -3, dy: -3)
                avatarRing = partHover
                avatarRing.setFill()
                NSBezierPath(roundedRect: halo, xRadius: halo.height / 2, yRadius: halo.height / 2).fill()
                if row.item.assignees.isEmpty {
                    // Where an avatar would be, as Linear shows for an unassigned issue.
                    let circle = NSRect(x: rect.maxX - 18, y: midY - 9, width: 18, height: 18).insetBy(dx: 1.5, dy: 1.5)
                    let dashed = NSBezierPath(ovalIn: circle)
                    dashed.lineWidth = 1.2
                    dashed.setLineDash([2.2, 2], count: 2, phase: 0)
                    NSColor(Theme.textTertiary).setStroke()
                    dashed.stroke()
                }
            }
        }
        drawAvatars(row.item.assignees, rightEdge: right, midY: midY, ring: avatarRing, context: context)
        right -= 30 + 10
        date.draw(at: NSPoint(x: right - dateSize.width, y: midY - dateSize.height / 2))
        dateRect = NSRect(x: right - dateSize.width, y: midY - 9, width: dateSize.width, height: 18)
        right -= 52 + 10
        if let dueText {
            let icon = dueIcon?.size ?? .zero
            let width = 7 + icon.width + 4 + dueSize.width + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            parts.append((.dueDate, rect))
            drawChip(rect, hovered: hoveredPart == .dueDate)
            dueIcon?.draw(
                in: NSRect(x: rect.minX + 7, y: midY - icon.height / 2, width: icon.width, height: icon.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
            dueText.draw(at: NSPoint(x: rect.minX + 7 + icon.width + 4, y: midY - dueSize.height / 2))
            right = rect.minX - 10
        }
        if let project {
            let width = min(projectSize.width, 160)
            project.draw(with: NSRect(x: right - width, y: midY - projectSize.height / 2, width: width, height: projectSize.height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            right -= width + 10
        }
        if let milestoneText {
            let textWidth = min(milestoneSize.width, 120)
            let width = 7 + 10 + 5 + textWidth + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            if rect.minX > x + 160 {
                parts.append((.milestone, rect))
                drawChip(rect, hovered: hoveredPart == .milestone)
                PlanningGlyph.drawMilestone(row.milestoneMark, in: CGRect(x: rect.minX + 7, y: midY - 5, width: 10, height: 10), cg: context)
                milestoneText.draw(
                    with: NSRect(x: rect.minX + 7 + 10 + 5, y: midY - milestoneSize.height / 2, width: textWidth, height: milestoneSize.height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
                )
                right = rect.minX - 6
            }
        }
        // The project's own fields the view shows, as far as there is room.
        for field in row.chips.reversed() {
            let text = NSAttributedString(string: field.text, attributes: [
                .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor(Theme.textSecondary),
            ])
            let textSize = text.size()
            let textWidth = min(textSize.width, 120)
            let width = 7 + 10 + 5 + textWidth + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            guard rect.minX > x + 160 else { break }
            // An iteration opens its picker, as the milestone does.
            let kind: PickerKind? = field.icon == .iteration ? .iteration(fieldId: field.fieldId) : nil
            if let kind { parts.append((kind, rect)) }
            drawChip(rect, hovered: kind != nil && hoveredPart == kind)
            let icon = CGRect(x: rect.minX + 7, y: midY - 5, width: 10, height: 10)
            switch field.icon {
            case .option(let color): PlanningGlyph.drawDot(color, in: icon.insetBy(dx: -1, dy: -1), cg: context)
            case .iteration: MenuIcons.symbol("arrow.triangle.2.circlepath", color: Theme.textTertiary)?.draw(in: icon)
            case .date: MenuIcons.symbol("calendar", color: Theme.textTertiary)?.draw(in: icon)
            case .text: MenuIcons.symbol("text.alignleft", color: Theme.textTertiary)?.draw(in: icon)
            }
            text.draw(
                with: NSRect(x: rect.minX + 7 + 10 + 5, y: midY - textSize.height / 2, width: textWidth, height: textSize.height),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
            )
            right = rect.minX - 6
        }
        var labelsRect: NSRect?
        for label in labels.reversed() {
            let textSize = label.size
            let width = textSize.width + 7 + 7 + 5 + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            guard rect.minX > x + 120 else { break }
            labelsRect = labelsRect.map { $0.union(rect) } ?? rect
            let tint = onAccent ? NSColor.white.withAlphaComponent(canEditFields && hoveredPart == .labels ? 0.3 : 0.2)
                : label.color.withAlphaComponent(canEditFields && hoveredPart == .labels ? 0.24 : 0.14)
            tint.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            label.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 7, y: midY - 3.5, width: 7, height: 7)).fill()
            label.text.draw(at: NSPoint(x: rect.minX + 19, y: midY - textSize.height / 2))
            right = rect.minX - 6
        }

        if canEditFields, let labelsRect { parts.append((.labels, labelsRect)) }

        // The title takes what is left, with the sub-issue count and, when blocked, a flag with what blocks it
        // directly after it, and the parent of a sub-issue whose parent is elsewhere.
        let subWidth: CGFloat? = subCount == nil ? nil : subCountSize.width + 7 + 11 + 4 + 7
        let blockedWidth: CGFloat? = row.blocker == nil ? nil : blockerText == nil ? 26 : 7 + 11 + 4 + blockerSize.width + 7
        let beside = (subWidth.map { $0 + 10 } ?? 0) + (blockedWidth.map { $0 + 6 } ?? 0)
        let hintWidth: CGFloat? = parentHint == nil ? nil : 7 + 11 + 4 + parentHintSize.width + 7
        // The parent keeps some room as long as the title keeps more.
        let hintRoom = hintWidth.map { min($0, 200) + 10 } ?? 0
        let reserve = right - 12 - x - beside - hintRoom >= 200 ? hintRoom : 0
        let available = max(40, right - 12 - x - beside - reserve)
        let titleWidth = min(titleSize.width, available)
        title.draw(
            with: NSRect(x: x, y: midY - titleSize.height / 2, width: available, height: titleSize.height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
        if let subCount, let subWidth {
            let rect = NSRect(x: x + titleWidth + 10, y: midY - 10, width: subWidth, height: 20)
            parts.append((.subIssues, rect))
            drawChip(rect, hovered: hoveredPart == .subIssues)
            let origin = NSPoint(x: rect.minX + 7, y: midY - 5.5)
            let glyph = NSBezierPath()
            glyph.move(to: NSPoint(x: origin.x + 2.3, y: origin.y + 1.8))
            glyph.line(to: NSPoint(x: origin.x + 2.3, y: origin.y + 5.5))
            glyph.curve(
                to: NSPoint(x: origin.x + 4.1, y: origin.y + 7.3),
                controlPoint1: NSPoint(x: origin.x + 2.3, y: origin.y + 6.7),
                controlPoint2: NSPoint(x: origin.x + 2.9, y: origin.y + 7.3)
            )
            glyph.line(to: NSPoint(x: origin.x + 6, y: origin.y + 7.3))
            glyph.lineWidth = 1.2
            glyph.lineCapStyle = .round
            (onAccent ? NSColor.white : NSColor(Theme.textSecondary)).setStroke()
            glyph.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: origin.x + 6.2, y: origin.y + 5.8, width: 3.1, height: 3.1))
            dot.lineWidth = 1.2
            dot.stroke()
            subCount.draw(at: NSPoint(x: rect.minX + 7 + 11 + 4, y: midY - subCountSize.height / 2))
        }
        var afterTitle = x + titleWidth + 10 + (subWidth.map { $0 + 6 } ?? 0)
        if let blockedWidth {
            let after = afterTitle
            afterTitle += blockedWidth + 6
            let rect = NSRect(x: after, y: midY - 10, width: blockedWidth, height: 20)
            parts.append((.blockedBy, rect))
            drawChip(rect, hovered: hoveredPart == .blockedBy)
            if let flag = onAccent ? Self.blockedFlagOnAccent : Self.blockedFlag {
                let size = flag.size
                let flagX = blockerText == nil ? rect.midX - size.width / 2 : rect.minX + 7 + (11 - size.width) / 2
                flag.draw(
                    in: NSRect(x: flagX, y: midY - size.height / 2, width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                )
            }
            blockerText?.draw(at: NSPoint(x: rect.minX + 7 + 11 + 4, y: midY - blockerSize.height / 2))
        }
        if let parentHint, let hintWidth {
            let width = min(hintWidth, right - 12 - afterTitle)
            if width >= 70 {
                let rect = NSRect(x: afterTitle, y: midY - 10, width: width, height: 20)
                let kind: PickerKind = row.parentIsEpic ? .epic : .parent
                parts.append((kind, rect))
                if hoveredPart == kind { drawChip(rect, hovered: true) }
                if row.parentIsEpic {
                    PlanningGlyph.drawEpic(in: CGRect(x: rect.minX + 6, y: midY - 6, width: 12, height: 12), cg: context)
                } else if let arrow = Self.parentArrow {
                    let size = arrow.size
                    arrow.draw(
                        in: NSRect(x: rect.minX + 7, y: midY - size.height / 2, width: size.width, height: size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                    )
                }
                let textX = rect.minX + 7 + 11 + 4
                parentHint.draw(
                    with: NSRect(x: textX, y: midY - parentHintSize.height / 2, width: rect.maxX - 7 - textX, height: parentHintSize.height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
                )
            }
        }
        // Tooltips follow the parts; rebuilt only when they moved.
        if parts.map(\.rect) != self.parts.map(\.rect) || foldRect != tooltipFoldRect || numberRect != self.numberRect || toolTipsNeedUpdate {
            toolTipsNeedUpdate = false
            tooltipFoldRect = foldRect
            self.numberRect = numberRect
            removeAllToolTips()
            for part in parts { addToolTip(part.rect.insetBy(dx: -3, dy: -4), owner: self, userData: nil) }
            if let foldRect { addToolTip(foldRect.insetBy(dx: -3, dy: -4), owner: self, userData: nil) }
            addToolTip(numberRect.insetBy(dx: -3, dy: -4), owner: self, userData: nil)
            if dateRect.width > 0 { addToolTip(dateRect, owner: self, userData: nil) }
        }
        self.parts = parts
    }

    private var toolTipsNeedUpdate = true
    private var tooltipFoldRect: NSRect?

    /// Lines from the parents above down to this row: a straight one through the row for each level whose
    /// sub-issues go on below it, a branch into this row's status icon, and a line from this row's status icon
    /// down to its own sub-issues when they show.
    private func drawTree(_ row: IssueRowModel, from base: CGFloat, midY: CGFloat) {
        let depth = min(row.nest.depth, Self.deepestIndent)
        let height = bounds.height
        let path = NSBezierPath()
        for level in 0..<depth {
            let lineX = base + CGFloat(level) * Self.indent + 7
            let continues = row.nest.continues.indices.contains(level) && row.nest.continues[level]
            if level < depth - 1 {
                if continues {
                    path.move(to: NSPoint(x: lineX, y: 0))
                    path.line(to: NSPoint(x: lineX, y: height))
                }
                continue
            }
            let end = base + CGFloat(depth) * Self.indent - 3
            if continues {
                path.move(to: NSPoint(x: lineX, y: 0))
                path.line(to: NSPoint(x: lineX, y: height))
                path.move(to: NSPoint(x: lineX, y: midY))
                path.line(to: NSPoint(x: end, y: midY))
            } else {
                let radius: CGFloat = 5
                path.move(to: NSPoint(x: lineX, y: 0))
                path.line(to: NSPoint(x: lineX, y: midY - radius))
                path.curve(
                    to: NSPoint(x: lineX + radius, y: midY),
                    controlPoint1: NSPoint(x: lineX, y: midY - radius * 0.45),
                    controlPoint2: NSPoint(x: lineX + radius * 0.45, y: midY)
                )
                path.line(to: NSPoint(x: end, y: midY))
            }
        }
        if row.nested != nil, !row.folded {
            let lineX = base + CGFloat(depth) * Self.indent + 7
            path.move(to: NSPoint(x: lineX, y: midY + 10))
            path.line(to: NSPoint(x: lineX, y: height))
        }
        guard !path.isEmpty else { return }
        path.lineWidth = 1
        NSColor(Theme.treeLine).setStroke()
        path.stroke()
    }

    /// A chevron that points down while the sub-issues show and to the right while they are folded in.
    static func drawFoldArrow(folded: Bool, center: NSPoint, color: NSColor) {
        let path = NSBezierPath()
        if folded {
            path.move(to: NSPoint(x: center.x - 1.5, y: center.y - 3.5))
            path.line(to: NSPoint(x: center.x + 2, y: center.y))
            path.line(to: NSPoint(x: center.x - 1.5, y: center.y + 3.5))
        } else {
            path.move(to: NSPoint(x: center.x - 3.5, y: center.y - 1.5))
            path.line(to: NSPoint(x: center.x, y: center.y + 2))
            path.line(to: NSPoint(x: center.x + 3.5, y: center.y - 1.5))
        }
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static var parentArrow: NSImage? {
        NSImage(systemSymbolName: "arrow.turn.left.up", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 9, weight: .medium).applying(.init(paletteColors: [NSColor(Theme.textTertiary)]))
        )
    }

    private static var blockedFlag: NSImage? {
        NSImage(systemSymbolName: "flag.fill", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 9, weight: .medium).applying(.init(paletteColors: [NSColor(Theme.blocked)]))
        )
    }

    /// In a picked row, which is filled with the accent colour, the flag is white like the rest of the row.
    private static var blockedFlagOnAccent: NSImage? {
        NSImage(systemSymbolName: "flag.fill", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 9, weight: .medium).applying(.init(paletteColors: [.white]))
        )
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let row else { return "" }
        if isOnFold(point) {
            return String(localized: row.folded ? .unfoldSubIssuesTooltip(count: row.nested ?? 0) : .foldSubIssuesTooltip)
        }
        if let part = part(at: point) { return model?.tooltip(part.kind, for: row.item) ?? "" }
        // A project's rows leave out the repository; as a project can span several, the number names it.
        if numberRect.insetBy(dx: -3, dy: -4).contains(point) { return row.item.reference ?? "" }
        if dateRect.insetBy(dx: -3, dy: -4).contains(point), let updated = row.item.updatedAt {
            var lines = [String(localized: .updatedOnDateTooltip(date: updated.formatted(date: .long, time: .shortened)))]
            if let created = row.item.createdAt {
                lines.append(String(localized: .createdOnDateTooltip(date: created.formatted(date: .long, time: .shortened))))
            }
            return lines.joined(separator: "\n")
        }
        return ""
    }

    private func drawCheckbox(checked: Bool, center: NSPoint) {
        let box = NSRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
        let shape = NSBezierPath(roundedRect: box.insetBy(dx: checked ? 0 : 0.6, dy: checked ? 0 : 0.6), xRadius: 4, yRadius: 4)
        if checked {
            // On the accent-filled row the box is white with the mark in the accent colour.
            NSColor.white.setFill()
            shape.fill()
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: box.minX + 3.6, y: box.midY + 0.2))
            mark.line(to: NSPoint(x: box.minX + 6, y: box.midY + 2.6))
            mark.line(to: NSPoint(x: box.maxX - 3.4, y: box.midY - 2.6))
            mark.lineWidth = 1.7
            mark.lineCapStyle = .round
            mark.lineJoinStyle = .round
            NSColor(Theme.accentFill).setStroke()
            mark.stroke()
        } else {
            shape.lineWidth = 1.2
            NSColor(Theme.textTertiary).setStroke()
            shape.stroke()
        }
    }

    /// The quiet parts of a row (due date, sub-issues, milestone, fields) are text with a symbol, as Mail and
    /// Reminders write them; under the pointer they light up as the button they are.
    private func drawChip(_ rect: NSRect, hovered: Bool) {
        guard hovered else { return }
        (row?.selected == true ? NSColor.white.withAlphaComponent(0.22) : NSColor(Theme.partHover)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }

    private func drawPriority(_ level: PriorityLevel, x: CGFloat, midY: CGFloat, onAccent: Bool = false) {
        if level == .urgent {
            let rect = NSRect(x: x + 1, y: midY - 6, width: 12, height: 12)
            NSColor(Theme.urgent).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            let mark = NSAttributedString(string: "!", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .heavy),
                .foregroundColor: NSColor(Theme.onColor),
            ])
            let markSize = mark.size()
            mark.draw(at: NSPoint(x: rect.midX - markSize.width / 2, y: rect.midY - markSize.height / 2))
            return
        }
        let bars: [(CGFloat, Bool)] = [(4, level >= .low), (7, level >= .medium), (10, level >= .high)]
        for (index, bar) in bars.enumerated() {
            (onAccent ? NSColor.white.withAlphaComponent(bar.1 ? 1 : 0.35) : NSColor(bar.1 ? Theme.textBody : Theme.barOff)).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: x + CGFloat(index) * 5, y: midY + 6 - bar.0, width: 3, height: bar.0),
                xRadius: 1, yRadius: 1
            ).fill()
        }
    }

    private func drawAvatars(_ people: [Person], rightEdge: CGFloat, midY: CGFloat, ring: NSColor, context: CGContext) {
        let shown = Array(people.prefix(3))
        let diameter: CGFloat = 18
        for (index, person) in shown.enumerated().reversed() {
            let offset = CGFloat(shown.count - 1 - index) * 13
            let rect = NSRect(x: rightEdge - diameter - offset, y: midY - diameter / 2, width: diameter, height: diameter)
            // A ring in the row colour separates overlapping avatars.
            if shown.count > 1 {
                ring.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5)).fill()
            }
            if let url = person.avatarUrl, let image = AvatarCache.shared.cached(url) {
                context.saveGState()
                NSBezierPath(ovalIn: rect).addClip()
                image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
                context.restoreGState()
            } else {
                NSColor(Avatar.color(for: person.login)).setFill()
                NSBezierPath(ovalIn: rect).fill()
                let initials = NSAttributedString(string: String(person.login.prefix(2)).uppercased(), attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .foregroundColor: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1),
                ])
                let initialsSize = initials.size()
                initials.draw(at: NSPoint(x: rect.midX - initialsSize.width / 2, y: rect.midY - initialsSize.height / 2))
            }
        }
    }
}
#endif
