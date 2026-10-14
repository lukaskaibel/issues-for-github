import SwiftUI

/// What a board card shows, gathered up front so drawing needs no lookups.
struct CardModel: Equatable {
    var item: Item
    var priority: PriorityLevel
    var showsPriority: Bool
    /// Repository names only matter on boards that span more than one.
    var showsRepo: Bool
    var due: DueBadge?
    /// How many sub-issues hang under the card in its column, folded or not; nil when none do.
    var nested: Int?
    var folded = false
    /// A sub-issue whose parent is in another column names the parent.
    var showsParent = false
    /// Whether that parent is an epic, which it then names with the epic's icon.
    var parentIsEpic = false
    /// The milestone it is planned for, on boards that aren't a milestone's.
    var milestone: String?
    var milestoneMark: MilestoneMark = .upcoming
}

extension AppModel {
    /// What a card shows; `nesting` is its column's, for the sub-issues hanging under it.
    func cardModel(for item: Item, in nesting: Nesting? = nil, showsMilestone: Bool = true) -> CardModel {
        CardModel(
            item: item,
            priority: priorityLevel(of: item),
            showsPriority: project(of: item)?.priorityFieldId != nil,
            showsRepo: repos(projectId: item.projectId).count > 1,
            due: dueBadge(for: item),
            nested: nesting?.nestedCounts[item.id],
            folded: nesting?.folded.contains(item.id) ?? false,
            showsParent: nesting.map { $0.namesParent(of: item) } ?? (item.parentNumber != nil),
            parentIsEpic: item.parentId.flatMap { issue(contentId: $0) }?.isEpic ?? false,
            milestone: showsMilestone ? milestoneTitle(of: item) : nil,
            milestoneMark: milestoneMark(of: item)
        )
    }
}

/// A board card, painted in a single pass at a height worked out in advance. Built from separate
/// views, a card takes over ten milliseconds to create and measure, which shows as stutter when a
/// long column scrolls.
struct CardView: View, Equatable {
    var card: CardModel
    var width: CGFloat
    var highlighted = false
    /// Picked for a change to several issues at once.
    var selected = false
    var lifted = false
    /// Changes when avatar images finish loading, so cards repaint with them.
    var avatarVersion = 0
    /// The clickable part under the pointer, drawn with a soft highlight.
    var hoveredPart: PickerKind? = nil
    /// Whether the pointer is on the arrow that folds the sub-issues under the card.
    var hoveringFold = false

    static let padding = CGSize(width: 12, height: 10)
    #if os(macOS)
    static let titleSize: CGFloat = 13
    static let lineHeight: CGFloat = 16
    static let metaSize: CGFloat = 12
    static let chipSize: CGFloat = 11
    #else
    // Cards on the iPad are read at arm's length and touched, so their type is a size up.
    static let titleSize: CGFloat = 14.5
    static let lineHeight: CGFloat = 18
    static let metaSize: CGFloat = 13
    static let chipSize: CGFloat = 12
    #endif

    var body: some View {
        let titleHeight = Self.titleHeight(card.item.title, width: width - 2 * Self.padding.width)
        Canvas { context, size in
            CardPainter(context: context, size: size, titleHeight: titleHeight).draw(self)
        }
        .frame(width: width, height: Self.height(titleHeight: titleHeight))
        .accessibilityElement()
        .accessibilityLabel(
            "\(card.item.displayNumber) \(card.item.title)" + (card.due.map { ", \($0.tooltip)" } ?? "")
                + (card.item.parentNumber.map { number in
                    ", " + String(localized: card.parentIsEpic
                        ? .epicTooltip(epic: card.item.parentTitle ?? "#\(number)") : .subIssueOf(number: "#\(number)"))
                } ?? "")
        )
        .accessibilityAddTraits(.isButton)
    }

    static func height(titleHeight: CGFloat) -> CGFloat {
        padding.height + 18 + 6 + titleHeight + 6 + 20 + padding.height
    }

    private static let titleFont = PlatformFont.systemFont(ofSize: titleSize, weight: .medium)
    private static let heights = NSCache<NSString, NSNumber>()

    /// Height of the title when wrapped to at most three lines.
    static func titleHeight(_ title: String, width: CGFloat) -> CGFloat {
        let key = "\(Int(width))|\(title)" as NSString
        if let cached = heights.object(forKey: key) { return CGFloat(cached.doubleValue) }
        let text = NSAttributedString(string: title, attributes: [.font: titleFont])
        let size = CGSize(width: width, height: .greatestFiniteMagnitude)
        #if os(macOS)
        let bounds = text.boundingRect(with: size, options: [.usesLineFragmentOrigin, .usesFontLeading])
        #else
        let bounds = text.boundingRect(with: size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        #endif
        let lines = min(3, max(1, Int((bounds.height / lineHeight).rounded())))
        let height = CGFloat(lines) * lineHeight
        heights.setObject(NSNumber(value: Double(height)), forKey: key)
        return height
    }
}

/// Where the clickable parts of each card were last drawn, in the card's own coordinates.
final class CardRegionStore: @unchecked Sendable {
    static let shared = CardRegionStore()
    private let lock = NSLock()
    private var regions: [String: [(kind: PickerKind, rect: CGRect)]] = [:]
    private var folds: [String: CGRect] = [:]

    func set(_ itemId: String, _ parts: [(kind: PickerKind, rect: CGRect)], fold: CGRect? = nil) {
        lock.lock()
        regions[itemId] = parts
        folds[itemId] = fold
        lock.unlock()
    }

    /// The arrow that folds the sub-issues under a card.
    func fold(_ itemId: String) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }
        return folds[itemId]
    }

    func parts(_ itemId: String) -> [(kind: PickerKind, rect: CGRect)] {
        lock.lock()
        defer { lock.unlock() }
        return regions[itemId] ?? []
    }
}

private struct CardPainter {
    var context: GraphicsContext
    var size: CGSize
    var titleHeight: CGFloat

    func draw(_ view: CardView) {
        let card = view.card
        let item = card.item
        let padding = CardView.padding
        var parts: [(kind: PickerKind, rect: CGRect)] = []
        var fold: CGRect?
        // Each part lights up in a shape that suits it, as in Linear: a small square behind an icon, a halo
        // around avatars, and chips in their own outline.
        func hovered(_ kind: PickerKind) -> Bool { view.hoveredPart == kind && !view.lifted }
        func part(_ kind: PickerKind, _ rect: CGRect) {
            parts.append((kind, rect))
        }
        defer { if !view.lifted { CardRegionStore.shared.set(item.id, parts, fold: fold) } }
        let outline = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: 8, style: .continuous)
        let fill = view.lifted ? Theme.cardLifted : view.selected ? Theme.selectionFill : (view.highlighted ? Theme.cardHover : Theme.card)
        let border = view.lifted ? Theme.cardLiftedBorder : view.selected ? Theme.selectionBorder : (view.highlighted ? Theme.cardHoverBorder : Theme.cardBorder)
        context.fill(outline, with: .color(fill))
        context.stroke(outline, with: .color(border), lineWidth: view.selected && !view.lifted ? 1.5 : 1)

        // Top line: the arrow that folds the sub-issues under the card, number, repository, pull-request mark, the
        // parent of a sub-issue whose parent is elsewhere, and assignees on the right.
        let topY = padding.height + 9
        var x = padding.width
        if card.nested != nil {
            let rect = CGRect(x: x - 3, y: topY - 7, width: 14, height: 14)
            fold = rect
            if view.hoveringFold, !view.lifted {
                context.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 5), with: .color(Theme.partHover))
            }
            context.stroke(
                Self.foldArrow(folded: card.folded, center: CGPoint(x: rect.midX, y: rect.midY)),
                with: .color(Theme.textSecondary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            x = rect.maxX + 5
        }
        let number = context.resolve(
            Text(item.displayNumber).font(.system(size: CardView.metaSize)).monospacedDigit()
                .foregroundStyle(view.lifted ? Theme.textSecondary : Theme.textTertiary)
        )
        context.draw(number, at: CGPoint(x: x, y: topY), anchor: .leading)
        x += number.measure(in: CGSize(width: 200, height: 40)).width + 6
        if card.showsRepo, let repo = item.repoShortName {
            let text = context.resolve(Text(repo).font(.system(size: CardView.metaSize)).foregroundStyle(Theme.textTertiary))
            let width = min(text.measure(in: CGSize(width: 400, height: 40)).width, size.width - x - 80)
            if width > 20 {
                context.draw(text, in: CGRect(x: x, y: topY - 8, width: width, height: 16))
                x += width + 6
            }
        }
        if item.kind == .pullRequest {
            context.draw(
                Text(Image(systemName: "arrow.triangle.pull")).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textTertiary),
                at: CGPoint(x: x, y: topY), anchor: .leading
            )
            x += 16
        }
        if card.showsParent, let parentNumber = item.parentNumber {
            let avatars = item.kind == .draft ? 0 : 18 + CGFloat(max(min(item.assignees.count, 3), 1) - 1) * 13
            let room = size.width - padding.width - avatars - 10 - x
            // An epic is named by its icon and title, like a project in Linear; another parent by its number.
            let label = card.parentIsEpic
                ? Text(item.parentTitle ?? "#\(parentNumber)")
                : Text("\(Image(systemName: "arrow.turn.left.up")) #\(parentNumber) \(item.parentTitle ?? "")")
            let text = context.resolve(label.font(.system(size: CardView.metaSize)).foregroundStyle(Theme.textTertiary))
            let icon: CGFloat = card.parentIsEpic ? 15 : 0
            let width = min(text.measure(in: CGSize(width: 600, height: 40)).width, room - 12 - icon)
            if width >= 48 {
                let rect = CGRect(x: x - 2, y: topY - 9, width: width + 12 + icon, height: 18)
                let kind: PickerKind = card.parentIsEpic ? .epic : .parent
                part(kind, rect)
                if hovered(kind) { chip(rect, hovered: true) }
                if card.parentIsEpic {
                    context.stroke(
                        PlanningGlyph.layers(in: CGRect(x: rect.minX + 5, y: topY - 6, width: 12, height: 12)), with: .color(Theme.epic),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )
                }
                context.draw(text, in: CGRect(x: rect.minX + 6 + icon, y: topY - 8, width: width, height: 16))
            }
        }
        var avatarRing = fill
        if item.kind != .draft {
            let count = CGFloat(max(min(item.assignees.count, 3), 1))
            let width = 18 + (count - 1) * 13
            let rect = CGRect(x: size.width - padding.width - width, y: topY - 9, width: width, height: 18)
            part(.assignees, rect)
            if hovered(.assignees) {
                let halo = rect.insetBy(dx: -3, dy: -3)
                context.fill(Path(roundedRect: halo, cornerRadius: halo.height / 2), with: .color(Theme.partHover))
                avatarRing = Theme.partHover
                if item.assignees.isEmpty { drawUnassigned(in: rect) }
            }
        }
        drawAvatars(item.assignees, rightEdge: size.width - padding.width, midY: topY, ring: avatarRing)

        // Title, wrapped to at most three lines.
        let titleRect = CGRect(x: padding.width, y: padding.height + 18 + 6, width: size.width - 2 * padding.width, height: titleHeight)
        context.draw(Text(item.title).font(.system(size: CardView.titleSize, weight: .medium)).foregroundStyle(Theme.text), in: titleRect)

        // Bottom line: priority, labels, sub-issue progress.
        let bottomY = titleRect.maxY + 6 + 10
        x = padding.width
        if card.showsPriority {
            let rect = CGRect(x: x, y: bottomY - 7, width: 14, height: 14)
            part(.priority, rect)
            if hovered(.priority) {
                context.fill(Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 5), with: .color(Theme.partHover))
            }
            drawPriority(card.priority, x: x, midY: bottomY)
            x += 14 + 6
        }
        // The due date comes last but always shows, so labels make room for it.
        var dueChip: (text: GraphicsContext.ResolvedText, width: CGFloat)?
        if let due = card.due {
            let text = context.resolve(
                Text("\(Image(systemName: "calendar")) \(due.label)").font(.system(size: CardView.chipSize)).foregroundStyle(due.tone.color)
            )
            dueChip = (text, text.measure(in: CGSize(width: 200, height: 40)).width + 14)
        }
        let limit = size.width - padding.width - (dueChip.map { $0.width + 6 } ?? 0)
        // Blocked by an open issue: a red flag first, so labels never push it off the card.
        if item.blockedByCount > 0 {
            let rect = CGRect(x: x, y: bottomY - 10, width: 26, height: 20)
            part(.blockedBy, rect)
            chip(rect, hovered: hovered(.blockedBy))
            context.draw(
                Text(Image(systemName: "flag.fill")).font(.system(size: CardView.chipSize - 2, weight: .medium)).foregroundStyle(Theme.blocked),
                at: CGPoint(x: rect.midX, y: bottomY), anchor: .center
            )
            x = rect.maxX + 6
        }
        var shown = 0
        // Labels are measured first, so the highlight can sit behind all of them.
        var labelLayout: [(label: LabelRef, text: GraphicsContext.ResolvedText, rect: CGRect)] = []
        var labelX = x
        for label in item.labels.prefix(2) {
            let text = context.resolve(Text(label.name).font(.system(size: CardView.chipSize)).foregroundStyle(Theme.textSecondary))
            let width = text.measure(in: CGSize(width: 400, height: 40)).width + 7 + 7 + 5 + 7
            guard labelX + width <= limit else { break }
            labelLayout.append((label, text, CGRect(x: labelX, y: bottomY - 10, width: width, height: 20)))
            labelX += width + 6
        }
        if item.kind != .draft, let first = labelLayout.first, let last = labelLayout.last {
            part(.labels, first.rect.union(last.rect))
        }
        for (label, text, rect) in labelLayout {
            chip(rect, hovered: hovered(.labels))
            context.fill(Path(ellipseIn: CGRect(x: rect.minX + 7, y: bottomY - 3.5, width: 7, height: 7)), with: .color(Theme.labelColor(label.color)))
            context.draw(text, at: CGPoint(x: rect.minX + 19, y: bottomY), anchor: .leading)
            x = rect.maxX + 6
            shown += 1
        }
        if item.labels.count > shown, shown > 0 {
            let text = context.resolve(Text("+\(item.labels.count - shown)").font(.system(size: CardView.chipSize)).foregroundStyle(Theme.textSecondary))
            let width = text.measure(in: CGSize(width: 100, height: 40)).width + 14
            if x + width <= limit {
                let rect = CGRect(x: x, y: bottomY - 10, width: width, height: 20)
                chip(rect)
                context.draw(text, at: CGPoint(x: rect.minX + 7, y: bottomY), anchor: .leading)
                x = rect.maxX + 6
            }
        }
        if item.subTotal > 0 {
            let text = context.resolve(
                Text("\(item.subCompleted)/\(item.subTotal)").font(.system(size: CardView.chipSize)).monospacedDigit().foregroundStyle(Theme.textSecondary)
            )
            let width = text.measure(in: CGSize(width: 200, height: 40)).width + 7 + 11 + 4 + 7
            if x + width <= limit {
                let rect = CGRect(x: x, y: bottomY - 10, width: width, height: 20)
                part(.subIssues, rect)
                chip(rect, hovered: hovered(.subIssues))
                let origin = CGPoint(x: rect.minX + 7, y: bottomY - 5.5)
                var glyph = Path()
                glyph.move(to: CGPoint(x: origin.x + 2.3, y: origin.y + 1.8))
                glyph.addLine(to: CGPoint(x: origin.x + 2.3, y: origin.y + 5.5))
                glyph.addQuadCurve(to: CGPoint(x: origin.x + 4.1, y: origin.y + 7.3), control: CGPoint(x: origin.x + 2.3, y: origin.y + 7.3))
                glyph.addLine(to: CGPoint(x: origin.x + 6, y: origin.y + 7.3))
                context.stroke(glyph, with: .color(Theme.textSecondary), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                context.stroke(
                    Path(ellipseIn: CGRect(x: origin.x + 6.2, y: origin.y + 5.8, width: 3.1, height: 3.1)),
                    with: .color(Theme.textSecondary), lineWidth: 1.2
                )
                context.draw(text, at: CGPoint(x: rect.minX + 7 + 11 + 4, y: bottomY), anchor: .leading)
                x = rect.maxX + 6
            }
        }
        if let dueChip {
            let rect = CGRect(x: x, y: bottomY - 10, width: dueChip.width, height: 20)
            part(.dueDate, rect)
            chip(rect, hovered: hovered(.dueDate))
            context.draw(dueChip.text, at: CGPoint(x: rect.minX + 7, y: bottomY), anchor: .leading)
            x = rect.maxX + 6
        }
        // The milestone last: it is the same for many cards, so it gives way to what tells them apart.
        if let milestone = card.milestone {
            let text = context.resolve(Text(milestone).font(.system(size: CardView.chipSize)).foregroundStyle(Theme.textSecondary))
            let textWidth = min(text.measure(in: CGSize(width: 400, height: 40)).width, 110)
            let width = 7 + 10 + 5 + textWidth + 7
            if x + width <= size.width - padding.width {
                let rect = CGRect(x: x, y: bottomY - 10, width: width, height: 20)
                part(.milestone, rect)
                chip(rect, hovered: hovered(.milestone))
                let diamond = CGRect(x: rect.minX + 7, y: bottomY - 5, width: 10, height: 10)
                let outline = PlanningGlyph.diamond(in: diamond, inset: 1.1)
                let color = card.milestoneMark.color
                switch card.milestoneMark {
                case .completed:
                    context.fill(outline, with: .color(color))
                case .current, .late:
                    context.stroke(outline, with: .color(color), lineWidth: 1.3)
                    context.fill(PlanningGlyph.diamond(in: diamond, inset: 3.4), with: .color(color))
                case .upcoming, .none:
                    context.stroke(outline, with: .color(color), lineWidth: 1.3)
                }
                context.draw(text, in: CGRect(x: rect.minX + 7 + 10 + 5, y: bottomY - 8, width: textWidth, height: 16))
            }
        }
    }

    /// A chevron that points down while the sub-issues show and to the right while they are folded in.
    static func foldArrow(folded: Bool, center: CGPoint) -> Path {
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
        return path
    }

    private func chip(_ rect: CGRect, hovered: Bool = false) {
        let outline = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 10)
        if hovered { context.fill(outline, with: .color(Theme.chipHover)) }
        context.stroke(outline, with: .color(hovered ? Theme.chipHoverBorder : Theme.chipBorder), lineWidth: 1)
    }

    /// Where an avatar would be: a dashed circle, shown when pointing at an unassigned issue's avatar spot.
    private func drawUnassigned(in rect: CGRect) {
        let circle = CGRect(x: rect.maxX - 18, y: rect.midY - 9, width: 18, height: 18).insetBy(dx: 1.5, dy: 1.5)
        context.stroke(Path(ellipseIn: circle), with: .color(Theme.textTertiary), style: StrokeStyle(lineWidth: 1.2, dash: [2.2, 2]))
    }

    private func drawPriority(_ level: PriorityLevel, x: CGFloat, midY: CGFloat) {
        if level == .urgent {
            let rect = CGRect(x: x + 1, y: midY - 6, width: 12, height: 12)
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Theme.urgent))
            context.draw(
                Text("!").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.onColor),
                at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center
            )
            return
        }
        let bars: [(CGFloat, Bool)] = [(4, level >= .low), (7, level >= .medium), (10, level >= .high)]
        for (index, bar) in bars.enumerated() {
            let rect = CGRect(x: x + CGFloat(index) * 5, y: midY + 6 - bar.0, width: 3, height: bar.0)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(bar.1 ? Theme.textBody : Theme.barOff))
        }
    }

    private func drawAvatars(_ people: [Person], rightEdge: CGFloat, midY: CGFloat, ring: Color) {
        let shown = Array(people.prefix(3))
        let diameter: CGFloat = 18
        for (index, person) in shown.enumerated().reversed() {
            let offset = CGFloat(shown.count - 1 - index) * 13
            let rect = CGRect(x: rightEdge - diameter - offset, y: midY - diameter / 2, width: diameter, height: diameter)
            // A ring in the card colour separates overlapping avatars.
            if shown.count > 1 {
                context.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(ring))
            }
            if let url = person.avatarUrl, let image = AvatarCache.shared.cached(url) {
                var clipped = context
                clipped.clip(to: Path(ellipseIn: rect))
                clipped.draw(Image(platformImage: image).interpolation(.high), in: rect)
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(Avatar.color(for: person.login)))
                context.draw(
                    Text(String(person.login.prefix(2)).uppercased())
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: 0x111214)),
                    at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center
                )
            }
        }
    }
}

/// On the board, the lines from a parent card down to the sub-issue cards hanging under it: drawn in the gutter
/// left of a nested card and up through the gap above it, to the parent card's bottom edge.
struct CardTreeLines: View {
    /// Sub-issue cards hang this much further in per level, down to a few levels.
    static let indent: CGFloat = 16
    static let deepest = 3

    var place: Nesting.Place
    /// The gap between cards, which the lines bridge.
    var gap: CGFloat
    /// Where the branch meets the card, from the card's top: beside its first line.
    var branchY: CGFloat = 19

    var body: some View {
        Canvas { context, size in
            let depth = min(place.depth, Self.deepest)
            var path = Path()
            for level in 0..<depth {
                let lineX = CGFloat(level) * Self.indent + Self.indent / 2
                let continues = place.continues.indices.contains(level) && place.continues[level]
                if level < depth - 1 {
                    if continues {
                        path.move(to: CGPoint(x: lineX, y: 0))
                        path.addLine(to: CGPoint(x: lineX, y: size.height))
                    }
                    continue
                }
                let y = gap + branchY
                let end = CGFloat(depth) * Self.indent
                if continues {
                    path.move(to: CGPoint(x: lineX, y: 0))
                    path.addLine(to: CGPoint(x: lineX, y: size.height))
                    path.move(to: CGPoint(x: lineX, y: y))
                    path.addLine(to: CGPoint(x: end, y: y))
                } else {
                    let radius: CGFloat = 5
                    path.move(to: CGPoint(x: lineX, y: 0))
                    path.addLine(to: CGPoint(x: lineX, y: y - radius))
                    path.addQuadCurve(to: CGPoint(x: lineX + radius, y: y), control: CGPoint(x: lineX, y: y))
                    path.addLine(to: CGPoint(x: end, y: y))
                }
            }
            context.stroke(path, with: .color(Theme.treeLine), lineWidth: 1)
        }
        .padding(.top, -gap)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The edge of a second card peeking out under a card whose sub-issues are folded into it, or that carries them
/// along in a drag.
/// The issues of an epic standing together in a column, while they are dragged by their header to move them all:
/// a card with the epic's name and how many of its issues come along, over the edge of a second card.
struct EpicGroupCard: View {
    var group: Nesting.EpicGroup
    var width: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            EpicIcon(size: CardView.lineHeight - 2)
                .frame(height: CardView.lineHeight)
            Text(group.epic.title)
                .font(.system(size: CardView.titleSize, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: CardView.lineHeight, alignment: .leading)
            Text("\(group.count)")
                .font(.system(size: CardView.metaSize))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(height: CardView.lineHeight)
        }
        .padding(.horizontal, CardView.padding.width)
        .padding(.vertical, CardView.padding.height)
        .frame(width: width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.cardLifted))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.cardLiftedBorder, lineWidth: 1))
        .background(alignment: .top) { CardStackEdge() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.epicGroupSpoken(epic: group.epic.title, count: group.count)))
    }
}

struct CardStackEdge: View {
    static let height: CGFloat = 5

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .padding(.horizontal, 6)
            .offset(y: Self.height)
            .accessibilityHidden(true)
    }
}
