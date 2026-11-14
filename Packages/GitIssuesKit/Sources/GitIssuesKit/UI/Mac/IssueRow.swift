#if os(macOS)
import AppKit
import SwiftUI

/// What one row of issues shows, gathered up front so drawing needs no lookups. The same row stands for an issue
/// wherever the Mac lists issues: a project's list, My Issues and All Issues, and on an issue's page its sub-issues
/// and the issues it is blocked by or blocks (`IssueRowView`).
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
    /// Whether its parts open their pickers. Not for an issue known only from GitHub, such as a sub-issue on none of
    /// your boards, whose status icon only opens or closes it.
    var editable = true
    /// Whether it can be picked, with its checkbox or a ⌘-click: in the lists and among an issue's sub-issues.
    var pickable = true
    /// While the sub-issues under it are read for the first time, a spinner stands where its fold arrow goes.
    var foldWaiting = false
    /// A button at the start of the row under the pointer, which takes it off the list it is in: an issue another one is
    /// blocked by or blocks.
    var removable = false
    /// An issue known only from GitHub, as another one's sub-issue or as an issue it is blocked by or blocks: a click
    /// opens it on GitHub, which its tooltip says.
    var standIn: StandIn?

    enum StandIn: Equatable {
        /// Its status icon closes it or opens it again.
        case subIssue
        case relation
    }
}

extension AppModel {
    /// The row of `item`. What every row shows the same way is worked out here; what depends on the list, such as where
    /// the row hangs in it and what its groups say already, is passed in.
    func issueRow(
        _ item: Item, projectTitle: String? = nil, selected: Bool = false, selecting: Bool = false,
        nest: Nesting.Place = Nesting.Place(), nested: Int? = nil, folded: Bool = false, showsParent: Bool = false,
        milestone: String?, chips: [FieldChip]
    ) -> IssueRowModel {
        IssueRowModel(
            item: item, glyph: glyph(of: item), priority: priorityLevel(of: item),
            showsPriority: project(of: item)?.priorityFieldId != nil,
            showsStatus: !item.isOnBoard || project(of: item)?.statusFieldId != nil,
            projectTitle: projectTitle,
            due: dueBadge(for: item),
            blocker: blockerMark(for: item),
            selected: selected, selecting: selecting,
            nest: nest, nested: nested, folded: folded, showsParent: showsParent,
            parentIsEpic: item.parentId.flatMap { issue(contentId: $0) }?.isEpic ?? false,
            milestone: milestone,
            milestoneMark: milestoneMark(of: item),
            chips: chips
        )
    }

    /// The row of an issue the app knows only from another one's sub-issues or relations: open or closed, its number,
    /// title and people, and what blocks it as far as known.
    func issueRow(
        standingInFor item: Item, as standIn: IssueRowModel.StandIn, nest: Nesting.Place = Nesting.Place(), nested: Int? = nil, folded: Bool = false
    ) -> IssueRowModel {
        IssueRowModel(
            item: item, glyph: glyph(of: item), priority: .none,
            showsPriority: false, showsStatus: standIn == .subIssue, blocker: blockerMark(for: item),
            nest: nest, nested: nested, folded: folded, editable: false, pickable: false, standIn: standIn
        )
    }
}

/// One issue, drawn directly. Configuring and drawing a recycled cell takes a fraction of a millisecond.
final class IssueRowCell: PaintedCell, NSViewToolTipOwner {
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
    /// The texts of the project's fields the view shows.
    private var chipTexts: [(text: NSAttributedString, size: NSSize)] = []
    /// How many labels the issue shows in all, and "+2" for each number of them that may not fit.
    private var labelCount = 0
    private var moreLabels: [Int: (text: NSAttributedString, size: NSSize)] = [:]
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

    /// The button that takes the issue off the list it is in, at the end of a removable row; where it was drawn last.
    private(set) var removeRect: NSRect?
    var hoveringRemove = false {
        didSet { if hoveringRemove != oldValue { needsDisplay = true } }
    }

    func isOnRemove(_ point: NSPoint) -> Bool {
        removeRect?.contains(point) ?? false
    }

    /// What VoiceOver's press does: opens the issue. The list's table does that for its own rows.
    var pressAction: (() -> Void)?

    override func accessibilityPerformPress() -> Bool {
        guard let pressAction else { return super.accessibilityPerformPress() }
        pressAction()
        return true
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
                hoveringRemove = false
                parts = []
                foldRect = nil
                removeRect = nil
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
                // The calendar at the size and weight of the date, as cards write it.
                dueIcon = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
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
            chipTexts = row.chips.map { chip in
                let text = NSAttributedString(string: chip.text, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: secondary])
                return (text, text.size())
            }
            // Labels as cards show them (`LabelMark`), and "+2" for those that don't fit, made for each number of them
            // that can be left over.
            let shownLabels = item.shownLabels
            labelCount = shownLabels.count
            labels = shownLabels.prefix(LabelMark.inRow).map { label in
                let text = NSAttributedString(string: label.name, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: secondary])
                return (text, text.size(), NSColor(Theme.labelColor(label.color)))
            }
            moreLabels = [:]
            if labelCount > 1 {
                for count in max(1, labelCount - LabelMark.inRow)..<labelCount {
                    let text = NSAttributedString(string: "+\(count)", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: secondary])
                    moreLabels[count] = (text, text.size())
                }
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
        // The checkbox sits under the section headers' fold arrow; it shows on hover and while picking. A row that can't
        // be picked but can be taken off its list has the button for that there instead, so the row's columns stay in
        // line with the rows around it.
        if row.pickable, row.selected || row.selecting || highlighted {
            drawCheckbox(checked: row.selected, center: NSPoint(x: IssueTable.inset + 15, y: midY))
        }
        if row.removable, !row.pickable {
            let rect = NSRect(x: IssueTable.inset + 6, y: midY - 9, width: 18, height: 18)
            removeRect = rect
            if highlighted {
                if hoveringRemove {
                    NSColor(Theme.partHover).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
                }
                if let mark = Self.removeMark {
                    mark.draw(
                        in: NSRect(x: rect.midX - mark.size.width / 2, y: midY - mark.size.height / 2, width: mark.size.width, height: mark.size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                    )
                }
            }
        } else {
            removeRect = nil
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
        // Without a Priority field in the project there is nothing to show, as on a card; the place stays, so numbers and
        // titles line up with the rows around.
        if row.showsPriority { drawPriority(row.priority, x: x, midY: midY, onAccent: onAccent) }
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
        let glyph = onAccent ? row.glyph.onAccent : row.glyph
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
            // While its sub-issues are read the first time, the view holding the row shows a spinner here.
            if !row.foldWaiting {
                Self.drawFoldArrow(folded: row.folded, center: NSPoint(x: rect.midX, y: rect.midY), color: onAccent ? .white : NSColor(Theme.textSecondary))
            }
            x = rect.maxX + 8
        } else {
            foldRect = nil
        }
        // A pull request says so before its title, with the mark its card shows after the number.
        if row.item.kind == .pullRequest, let mark = onAccent ? Self.pullRequestMarkOnAccent : Self.pullRequestMark {
            mark.draw(
                in: NSRect(x: x, y: midY - mark.size.height / 2, width: mark.size.width, height: mark.size.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
            x += mark.size.width + 6
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
        // Room for two avatars, so dates stand in line; a third one pushes its row's date over rather than under it.
        right -= max(31, 18 + CGFloat(max(min(row.item.assignees.count, 3), 1) - 1) * 13) + 10
        date.draw(at: NSPoint(x: right - dateSize.width, y: midY - dateSize.height / 2))
        dateRect = NSRect(x: right - dateSize.width, y: midY - 9, width: dateSize.width, height: 18)
        right -= 52 + 10
        if let dueText {
            let icon = dueIcon?.size ?? .zero
            let width = 7 + icon.width + 3 + dueSize.width + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            parts.append((.dueDate, rect))
            drawChip(rect, hovered: hoveredPart == .dueDate)
            dueIcon?.draw(
                in: NSRect(x: rect.minX + 7, y: midY - icon.height / 2, width: icon.width, height: icon.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
            dueText.draw(at: NSPoint(x: rect.minX + 7 + icon.width + 3, y: midY - dueSize.height / 2))
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
                // Grey, as on cards: the same milestone repeats down the list; its shape still tells the current one, and
                // only one past its date keeps its colour. White on a picked row.
                let color: Color = onAccent ? .white : row.milestoneMark == .late ? Theme.overdue : Theme.textTertiary
                PlanningGlyph.drawMilestone(row.milestoneMark, in: CGRect(x: rect.minX + 7, y: midY - 5, width: 10, height: 10), cg: context, color: color)
                milestoneText.draw(
                    with: NSRect(x: rect.minX + 7 + 10 + 5, y: midY - milestoneSize.height / 2, width: textWidth, height: milestoneSize.height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
                )
                right = rect.minX - 6
            }
        }
        // The project's own fields the view shows, as far as there is room.
        for (field, chip) in zip(row.chips, chipTexts).reversed() {
            let text = chip.text
            let textSize = chip.size
            let textWidth = min(textSize.width, 120)
            let width = 7 + 10 + 5 + textWidth + 7
            let rect = NSRect(x: right - width, y: midY - 10, width: width, height: 20)
            guard rect.minX > x + 160 else { break }
            // An iteration opens its picker, as the milestone does.
            let kind: PickerKind? = field.icon == .iteration ? .iteration(fieldId: field.fieldId) : nil
            if let kind { parts.append((kind, rect)) }
            drawChip(rect, hovered: kind != nil && hoveredPart == kind)
            let icon = CGRect(x: rect.minX + 7, y: midY - 5, width: 10, height: 10)
            if case .option(let color) = field.icon {
                NSColor(Theme.optionColor(color) ?? Theme.textTertiary).setFill()
                NSBezierPath(ovalIn: icon.insetBy(dx: 1.5, dy: 1.5)).fill()
            } else if let symbol = Self.fieldSymbol(field.icon, onAccent: onAccent) {
                symbol.draw(
                    in: NSRect(x: icon.midX - symbol.size.width / 2, y: icon.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                )
            }
            text.draw(
                with: NSRect(x: rect.minX + 7 + 10 + 5, y: midY - textSize.height / 2, width: textWidth, height: textSize.height),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
            )
            right = rect.minX - 6
        }
        // Labels as cards show them (`LabelMark`): a dot in each one's colour and its name, as many as leave the title
        // its room, then "+2" for the others. Under the pointer they light up together, as the one button they are.
        func labelsWidth(_ count: Int) -> CGFloat {
            guard count > 0 else { return 0 }
            var width = labels.prefix(count).map { LabelMark.width(name: $0.size.width) }.reduce(0, +)
                + CGFloat(count - 1) * LabelMark.spacing
            if let more = moreLabels[labelCount - count] { width += LabelMark.spacing + LabelMark.inset + more.size.width + LabelMark.inset }
            return width
        }
        var fitting = labels.count
        while fitting > 0, right - labelsWidth(fitting) <= x + 120 { fitting -= 1 }
        if fitting > 0 {
            let width = labelsWidth(fitting)
            let labelsRect = NSRect(x: right - width, y: midY - LabelMark.height / 2, width: width, height: LabelMark.height)
            if canEditFields { parts.append((.labels, labelsRect)) }
            drawChip(labelsRect, hovered: canEditFields && hoveredPart == .labels)
            var labelX = labelsRect.minX
            for label in labels.prefix(fitting) {
                let dot = NSRect(x: labelX + LabelMark.inset, y: midY - LabelMark.dot / 2, width: LabelMark.dot, height: LabelMark.dot)
                label.color.setFill()
                NSBezierPath(ovalIn: dot).fill()
                if onAccent {
                    // On the accent of a picked row, a ring keeps a dot of a like colour apart from it.
                    NSColor.white.withAlphaComponent(0.9).setStroke()
                    let ring = NSBezierPath(ovalIn: dot.insetBy(dx: -0.5, dy: -0.5))
                    ring.lineWidth = 1
                    ring.stroke()
                }
                label.text.draw(at: NSPoint(x: dot.maxX + LabelMark.gap, y: midY - label.size.height / 2))
                labelX += LabelMark.width(name: label.size.width) + LabelMark.spacing
            }
            if let more = moreLabels[labelCount - fitting] {
                more.text.draw(at: NSPoint(x: labelX + LabelMark.inset, y: midY - more.size.height / 2))
            }
            right = labelsRect.minX - 6
        }

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
        titleRect = NSRect(x: x, y: midY - 9, width: titleWidth, height: 18)
        title.draw(
            with: NSRect(x: x, y: midY - titleSize.height / 2, width: available, height: titleSize.height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
        if let subCount, let subWidth {
            let rect = NSRect(x: x + titleWidth + 10, y: midY - 10, width: subWidth, height: 20)
            parts.append((.subIssues, rect))
            drawChip(rect, hovered: hoveredPart == .subIssues)
            context.draw(
                Marks.subIssue(in: CGRect(x: rect.minX + 7, y: midY - 5.5, width: 11, height: 11)),
                mark: (onAccent ? NSColor.white : NSColor(Theme.textSecondary)).cgColor, onColor: NSColor.white.cgColor
            )
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
                    // In the grey of the epic's name, as on cards: the epic's own colour is for its header and the roadmap.
                    PlanningGlyph.drawEpic(
                        in: CGRect(x: rect.minX + 6, y: midY - 6, width: 12, height: 12), cg: context,
                        color: onAccent ? Color.white.opacity(0.8) : Theme.textTertiary
                    )
                } else if let arrow = onAccent ? Self.parentArrowOnAccent : Self.parentArrow {
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
        // An issue known only from GitHub has nothing to pick from, but its status icon opens or closes it.
        if !row.editable { parts = parts.filter { $0.kind == .status } }
        // Tooltips follow the parts; rebuilt only when they moved.
        if parts.map(\.rect) != self.parts.map(\.rect) || foldRect != tooltipFoldRect || removeRect != tooltipRemoveRect
            || numberRect != self.numberRect || toolTipsNeedUpdate {
            toolTipsNeedUpdate = false
            tooltipFoldRect = foldRect
            tooltipRemoveRect = removeRect
            self.numberRect = numberRect
            removeAllToolTips()
            for part in parts { addToolTip(part.rect.insetBy(dx: -3, dy: -4), owner: self, userData: nil) }
            if let foldRect { addToolTip(foldRect.insetBy(dx: -3, dy: -4), owner: self, userData: nil) }
            if let removeRect { addToolTip(removeRect, owner: self, userData: nil) }
            if row.standIn != nil { addToolTip(titleRect, owner: self, userData: nil) }
            addToolTip(numberRect.insetBy(dx: -3, dy: -4), owner: self, userData: nil)
            if dateRect.width > 0 { addToolTip(dateRect, owner: self, userData: nil) }
        }
        self.parts = parts
    }

    private var toolTipsNeedUpdate = true
    private var tooltipRemoveRect: NSRect?
    /// Where the title was drawn, whose tooltip says that an issue known only from GitHub opens there.
    private var titleRect = NSRect.zero
    private var tooltipFoldRect: NSRect?

    /// Lines from the parents above down to this row: a straight one through the row for each level whose
    /// sub-issues go on below it, a branch into this row's status icon, and a line from this row's status icon
    /// down to its own sub-issues when they show.
    private func drawTree(_ row: IssueRowModel, from base: CGFloat, midY: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let depth = min(row.nest.depth, Self.deepestIndent)
        var path = Marks.treeLines(
            row.nest, deepest: Self.deepestIndent, lineX: { base + CGFloat($0) * Self.indent + 7 },
            branchY: midY, branchEnd: base + CGFloat(depth) * Self.indent - 3, height: bounds.height
        )
        if row.nested != nil, !row.folded {
            let lineX = base + CGFloat(depth) * Self.indent + 7
            path.move(to: CGPoint(x: lineX, y: midY + 10))
            path.addLine(to: CGPoint(x: lineX, y: bounds.height))
        }
        guard !path.isEmpty else { return }
        context.draw([Marks.Shape(path: path, stroke: StrokeStyle(lineWidth: 1))], mark: NSColor(Theme.treeLine).cgColor, onColor: NSColor(Theme.treeLine).cgColor)
    }

    /// The arrow that folds sub-issues in or out (`Marks.foldArrow`), for the list's views.
    static func drawFoldArrow(folded: Bool, center: NSPoint, color: NSColor) {
        NSGraphicsContext.current?.cgContext.draw(Marks.foldArrow(folded: folded, center: center), mark: color.cgColor, onColor: color.cgColor)
    }

    private static var parentArrow: NSImage? {
        NSImage(systemSymbolName: "arrow.turn.left.up", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 9, weight: .medium).applying(.init(paletteColors: [NSColor(Theme.textTertiary)]))
        )
    }

    private static var pullRequestMark: NSImage? {
        NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .medium).applying(.init(paletteColors: [NSColor(Theme.textTertiary)]))
        )
    }

    private static var pullRequestMarkOnAccent: NSImage? {
        NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .medium).applying(.init(paletteColors: [NSColor.white.withAlphaComponent(0.8)]))
        )
    }

    private static var parentArrowOnAccent: NSImage? {
        NSImage(systemSymbolName: "arrow.turn.left.up", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 9, weight: .medium).applying(.init(paletteColors: [NSColor.white.withAlphaComponent(0.8)]))
        )
    }

    /// A field's icon, as cards draw it: a symbol a little smaller than the text.
    private static var fieldSymbols: [String: NSImage] = [:]

    private static func fieldSymbol(_ icon: FieldChip.Icon, onAccent: Bool) -> NSImage? {
        let (name, size, weight): (String, CGFloat, NSFont.Weight) = switch icon {
        case .iteration: ("arrow.triangle.2.circlepath", 8, .semibold)
        case .date: ("calendar", 9, .regular)
        case .text: ("text.alignleft", 8, .regular)
        case .option: ("", 0, .regular)
        }
        guard !name.isEmpty else { return nil }
        let key = "\(name) \(onAccent)"
        if let image = fieldSymbols[key] { return image }
        let color = onAccent ? NSColor.white.withAlphaComponent(0.8) : NSColor(Theme.textTertiary)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: [color])))
        fieldSymbols[key] = image
        return image
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

    /// The mark of the button that takes the issue off its list, as the header's icon buttons draw theirs.
    private static var removeMark: NSImage? {
        NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11, weight: .medium).applying(.init(paletteColors: [NSColor(Theme.textSecondary)]))
        )
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let row else { return "" }
        if isOnRemove(point) { return String(localized: .removeRelation) }
        if let standIn = row.standIn {
            if part(at: point)?.kind == .status { return String(localized: row.item.isClosed ? .reopen : .markAsDoneTooltip) }
            if titleRect.contains(point) {
                return String(localized: standIn == .subIssue ? .subIssueOpensOnGitHub : .notOnYourBoardsOpensOnGitHub)
            }
        }
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
        // On the accent-filled row the box is white with the tick in the accent colour (`Marks.checkbox`).
        NSGraphicsContext.current?.cgContext.draw(
            Marks.checkbox(checked: checked, in: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)),
            mark: NSColor.white.cgColor, off: NSColor(Theme.textTertiary).cgColor, onColor: NSColor(Theme.accentFill).cgColor
        )
    }

    /// The quiet parts of a row (due date, sub-issues, milestone, fields) are text with a symbol, as Mail and
    /// Reminders write them; under the pointer they light up as the button they are.
    private func drawChip(_ rect: NSRect, hovered: Bool) {
        guard hovered else { return }
        (row?.selected == true ? NSColor.white.withAlphaComponent(0.22) : NSColor(Theme.partHover)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }

    private func drawPriority(_ level: PriorityLevel, x: CGFloat, midY: CGFloat, onAccent: Bool = false) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let box = CGRect(x: x, y: midY - 6, width: 14, height: 12)
        // The same shapes as cards and every view of a priority (`Marks.priority`); white on a picked row, but Urgent
        // keeps its colour, as a flag does.
        let mark = level == .urgent ? NSColor(Theme.urgent) : onAccent ? .white : NSColor(Theme.textBody)
        let off = onAccent ? NSColor.white.withAlphaComponent(0.35) : NSColor(Theme.barOff)
        context.draw(Marks.priority(level, in: box), mark: mark.cgColor, off: off.cgColor, onColor: NSColor(Theme.onColor).cgColor)
        if level == .urgent { Marks.drawUrgentMark(on: Marks.urgentSquare(in: box)) }
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

// MARK: - A row outside the list

/// An issue's row where the Mac lists issues outside the list: on an issue's page, its sub-issues and the issues it is
/// blocked by or blocks. It is the list's own row (`IssueRowCell`), and the pointer and clicks do what they do in the
/// list: a part lights up and opens its picker, the checkbox and ⌘- or Shift-clicks pick, the arrow folds what is under
/// it, a click elsewhere opens the issue, and a right-click shows its menu.
struct IssueRowView: View {
    @Environment(AppModel.self) private var model
    var row: IssueRowModel
    /// A click away from the row's parts.
    var open: () -> Void
    /// A click with ⌘ or Shift held, or one on the checkbox (`checkbox`): whether it picked the issue or let it go.
    var pick: (_ checkbox: Bool) -> Bool = { _ in false }
    /// The arrow of a row with sub-issues under it.
    var fold: () -> Void = {}
    /// The status icon of an issue known only from GitHub, which closes it or opens it again.
    var toggleClosed: () -> Void = {}
    /// Before a part opens its picker; picks of other issues go then, as in the list.
    var willOpenPart: () -> Void = {}
    /// The button at the end of a removable row.
    var remove: () -> Void = {}
    var menu: () -> NSMenu?

    var body: some View {
        IssueRowHostView(
            row: row, avatarVersion: model.avatarVersion,
            actions: IssueRowHost.Actions(
                open: open, pick: pick, fold: fold, toggleClosed: toggleClosed, willOpenPart: willOpenPart, remove: remove
            )
        )
        .frame(height: Theme.rowHeight)
        .glassContextMenu(menu)
    }
}

extension View {
    /// Rows of issues on a page hang into its margin by the room before their first icon, so that their priority icons
    /// line up with the headings and text above them, and the checkbox shows in the margin, as in the list it shows
    /// under the arrow of a section's header.
    func issueRowsOnPage() -> some View {
        padding(.leading, -(IssueTable.inset + 28)).padding(.trailing, -IssueTable.inset)
    }

    /// A heading among such rows stays in line with the page.
    func outOfIssueRows() -> some View {
        padding(.leading, IssueTable.inset + 28).padding(.trailing, IssueTable.inset)
    }
}

private struct IssueRowHostView: NSViewRepresentable {
    @Environment(AppModel.self) private var model
    var row: IssueRowModel
    var avatarVersion: Int
    var actions: IssueRowHost.Actions

    func makeNSView(context: Context) -> IssueRowHost {
        IssueRowHost()
    }

    func updateNSView(_ host: IssueRowHost, context: Context) {
        host.model = model
        host.actions = actions
        host.show(row, avatarVersion: avatarVersion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: IssueRowHost, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 480, height: Theme.rowHeight)
    }
}

/// Holds a list row outside the list's table and does for it what the table does for its rows: follows the pointer
/// over it and its parts, and acts on clicks.
final class IssueRowHost: NSView {
    struct Actions {
        var open: () -> Void
        var pick: (_ checkbox: Bool) -> Bool
        var fold: () -> Void
        var toggleClosed: () -> Void
        var willOpenPart: () -> Void
        var remove: () -> Void
    }

    weak var model: AppModel?
    var actions = Actions(open: {}, pick: { _ in false }, fold: {}, toggleClosed: {}, willOpenPart: {}, remove: {})
    let cell = IssueRowCell()
    private var row: IssueRowModel?
    private var avatarVersion = 0
    private var hovering = false
    private var pressed = false
    private var tracking: NSTrackingArea?
    /// Turns where the fold arrow goes while the sub-issues under the row are read the first time.
    private let spinner: NSProgressIndicator = {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isDisplayedWhenStopped = false
        return spinner
    }()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        cell.frame = bounds
        cell.autoresizingMask = [.width, .height]
        addSubview(cell)
        addSubview(spinner)
        cell.pressAction = { [weak self] in self?.actions.open() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    func show(_ row: IssueRowModel, avatarVersion: Int) {
        cell.model = model
        if row.standIn != self.row?.standIn || row.item.isClosed != self.row?.item.isClosed {
            // A sub-issue known only from GitHub is closed or opened again from its row, also with VoiceOver.
            cell.setAccessibilityCustomActions(row.standIn == .subIssue ? [
                NSAccessibilityCustomAction(name: String(localized: row.item.isClosed ? .reopenSubIssue : .markSubIssueAsDone)) { [weak self] in
                    self?.actions.toggleClosed()
                    return true
                },
            ] : [])
        }
        self.row = row
        cell.configure(row, highlighted: hovering)
        if avatarVersion != self.avatarVersion {
            self.avatarVersion = avatarVersion
            cell.needsDisplay = true
        }
        placeSpinner()
    }

    /// The row and its parts take their clicks here, not in the row's own view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    /// A click in a window in the background acts at once, as on the page's other buttons.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        placeSpinner()
    }

    private func placeSpinner() {
        guard let row, row.foldWaiting else {
            spinner.stopAnimation(nil)
            return
        }
        // The fold arrow's place is known once the row has been drawn at this width.
        cell.displayIfNeeded()
        guard let fold = cell.foldRect else { return }
        spinner.frame = NSRect(x: fold.midX - 8, y: fold.midY - 8, width: 16, height: 16)
        spinner.startAnimation(nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        point(at: event)
    }

    override func mouseMoved(with event: NSEvent) {
        point(at: event)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        cell.hoveredPart = nil
        cell.hoveringFold = false
        cell.hoveringRemove = false
        if let row { cell.configure(row, highlighted: false) }
    }

    /// Lights up the row, and the part under the pointer, as the list does.
    private func point(at event: NSEvent) {
        let local = cell.convert(event.locationInWindow, from: nil)
        hovering = true
        if let row { cell.configure(row, highlighted: true) }
        cell.hoveredPart = cell.part(at: local)?.kind
        cell.hoveringFold = cell.isOnFold(local)
        cell.hoveringRemove = cell.isOnRemove(local)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        pressed = false
        let local = cell.convert(event.locationInWindow, from: nil)
        guard cell.bounds.contains(local), let row, let model else { return }
        // In the order the list takes them: picking first, then the checkbox, the arrow, the parts, and the issue.
        if actions.pick(false) { return }
        if row.pickable, cell.checkboxRect.contains(local) {
            _ = actions.pick(true)
            return
        }
        if cell.isOnFold(local) {
            actions.fold()
            return
        }
        if cell.isOnRemove(local) {
            actions.remove()
            return
        }
        if let part = cell.part(at: local) {
            if !row.editable {
                actions.toggleClosed()
                return
            }
            actions.willOpenPart()
            Dropdown.show(below: part.rect, in: cell, model: model) { close in
                ItemPicker(kind: part.kind, itemId: row.item.id, close: close)
            }
            return
        }
        actions.open()
    }
}
#endif
