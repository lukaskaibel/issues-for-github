import SwiftUI

/// What a board card shows, gathered up front so drawing needs no lookups.
struct CardModel: Equatable {
    var item: Item
    var priority: PriorityLevel
    var showsPriority: Bool
    var due: DueBadge?
    /// What blocks it, when an open issue does; and that as VoiceOver reads it.
    var blocker: BlockerMark?
    var spokenBlocker: String?
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
    /// The project's own fields the view shows, such as an iteration or a "Workstream".
    var chips: [FieldChip] = []
    /// The chips as VoiceOver reads them, with their fields' names.
    var spokenChips: [String] = []
}

extension AppModel {
    /// What a card shows; `nesting` is its column's, for the sub-issues hanging under it.
    func cardModel(for item: Item, in nesting: Nesting? = nil, showsMilestone: Bool = true) -> CardModel {
        let chips = showsMilestone ? fieldChips(of: item, in: item.projectId.map { .project($0) }) : []
        let blocker = blockerMark(for: item)
        return CardModel(
            item: item,
            priority: priorityLevel(of: item),
            showsPriority: project(of: item)?.priorityFieldId != nil,
            due: dueBadge(for: item),
            blocker: blocker,
            spokenBlocker: blocker.map { _ in tooltip(.blockedBy, for: item) },
            nested: nesting?.nestedCounts[item.id],
            folded: nesting?.folded.contains(item.id) ?? false,
            showsParent: nesting.map { $0.namesParent(of: item) } ?? (item.parentNumber != nil),
            parentIsEpic: item.parentId.flatMap { issue(contentId: $0) }?.isEpic ?? false,
            milestone: showsMilestone && !viewPinsMilestone(projectId: item.projectId) ? milestoneTitle(of: item) : nil,
            milestoneMark: milestoneMark(of: item),
            chips: chips,
            spokenChips: chips.map(spokenChip)
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
    /// On the Mac board, what the column draws around a card, painted in the card's own pass so a row of a long
    /// column is a single view: the dashed slot where the lifted card would land, this tall, in place of the card;
    /// the edge of a second card peeking out under one whose sub-issues are folded into it; and the lines from a
    /// sub-issue's parent, in the gutter left of the card and through the gap above it. They reach past the card's
    /// frame, as the views they replace did, so the Canvas is that much bigger than the card it lays out as.
    var slotHeight: CGFloat? = nil
    var stackEdge = false
    var tree: Nesting.Place? = nil

    static let padding = CGSize(width: 12, height: 10)
    /// Rounder than a button, as Reminders' cards and Apple's grouped rows are.
    static let cornerRadius: CGFloat = 12
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
        let height = slotHeight ?? Self.height(titleHeight: titleHeight)
        let around = surroundings
        Canvas { context, size in
            #if DEBUG
            let began = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            defer { CardPaintTiming.add(since: began) }
            #endif
            var card = context
            card.translateBy(x: around.leading, y: around.top)
            CardPainter(context: card, size: CGSize(width: width, height: height), titleHeight: titleHeight).draw(self)
        }
        .frame(width: around.leading + width + around.trailing, height: around.top + height + around.bottom)
        .padding(EdgeInsets(top: -around.top, leading: -around.leading, bottom: -around.bottom, trailing: -around.trailing))
        .accessibilityElement()
        .accessibilityLabel(Self.spokenLabel(card))
        .accessibilityAddTraits(.isButton)
        // The slot stands in for the card being dragged.
        .accessibilityHidden(slotHeight != nil)
    }

    /// What VoiceOver reads for a card.
    static func spokenLabel(_ card: CardModel) -> String {
        "\(card.item.displayNumber) \(card.item.title)" + (card.spokenBlocker.map { ", \($0)" } ?? "")
            + (card.due.map { ", \($0.tooltip)" } ?? "")
            + (card.item.parentNumber.map { number in
                ", " + String(localized: card.parentIsEpic
                    ? .epicTooltip(epic: card.item.parentTitle ?? "#\(number)") : .subIssueOf(number: "#\(number)"))
            } ?? "")
            + card.spokenChips.map { ", \($0)" }.joined()
    }

    static func height(titleHeight: CGFloat) -> CGFloat {
        padding.height + 18 + 6 + titleHeight + 6 + 20 + padding.height
    }

    /// How far the Canvas, which clips, reaches past the card for what is drawn around it: the gutter and the gap
    /// above for the lines from a parent, and the edge of the card under it; for the slot, its dashes, which straddle
    /// its outline.
    private var surroundings: (leading: CGFloat, top: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        guard slotHeight == nil else { return (1, 1, 1, 1) }
        let gutter = tree.map { CGFloat(min($0.depth, CardTreeLines.deepest)) * CardTreeLines.indent } ?? 0
        return (gutter, tree == nil ? 0 : CardTreeLines.boardGap, stackEdge ? CardStackEdge.height : 0, 0)
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

#if DEBUG
/// How many cards were painted and how long that took, for the debug remote's board timing.
enum CardPaintTiming {
    nonisolated(unsafe) private(set) static var count = 0
    nonisolated(unsafe) private(set) static var milliseconds: Double = 0

    static func add(since began: UInt64) {
        count += 1
        milliseconds += Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - began) / 1e6
    }

    static func reset() {
        count = 0
        milliseconds = 0
    }
}
#endif

/// Where the clickable parts of each card were last drawn, in the card's own coordinates.
final class CardRegionStore: @unchecked Sendable {
    static let shared = CardRegionStore()
    private let lock = NSLock()
    private var regions: [String: [(kind: PickerKind, rect: CGRect)]] = [:]
    private var folds: [String: CGRect] = [:]
    private var numbers: [String: CGRect] = [:]

    func set(_ itemId: String, _ parts: [(kind: PickerKind, rect: CGRect)], fold: CGRect? = nil, number: CGRect? = nil) {
        lock.lock()
        regions[itemId] = parts
        folds[itemId] = fold
        numbers[itemId] = number
        lock.unlock()
    }

    /// The issue's number, which names its repository under the pointer.
    func number(_ itemId: String) -> CGRect? {
        lock.lock()
        defer { lock.unlock() }
        return numbers[itemId]
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

/// What painting a card needs again and again, kept from one paint to the next: the theme's colours, which follow the
/// appearance and are worked out through NSAppearance each time, and the texts, resolved and measured once. Working
/// them out was most of the time a card took to paint, on every hover change and for every card scrolled into view.
/// Kept apart for each look a card can be painted in, so a change of appearance, contrast, scale or text settings
/// paints with fresh ones. Cards are painted on the main thread; the lock keeps the store safe all the same.
final class CardPaintCache: @unchecked Sendable {
    static let shared = CardPaintCache()

    /// What the environment changes about the colours and texts of a card.
    struct Look: Hashable {
        var colorScheme: ColorScheme
        var contrast: ColorSchemeContrast
        var displayScale: CGFloat
        var locale: String
        var layoutDirection: LayoutDirection
        var legibilityWeight: LegibilityWeight?
        var dynamicTypeSize: DynamicTypeSize

        init(_ environment: EnvironmentValues) {
            colorScheme = environment.colorScheme
            contrast = environment.colorSchemeContrast
            displayScale = environment.displayScale
            locale = environment.locale.identifier
            layoutDirection = environment.layoutDirection
            legibilityWeight = environment.legibilityWeight
            dynamicTypeSize = environment.dynamicTypeSize
        }
    }

    /// A text ready to draw, and how wide it is where the painter measures it.
    struct Kept {
        var text: GraphicsContext.ResolvedText
        var width: CGFloat
    }

    private struct ColorKey: Hashable {
        var ink: CardInk
        var look: Look
    }

    private struct TextKey: Hashable {
        var text: CardText
        var look: Look
    }

    private let lock = NSLock()
    private var colors: [ColorKey: Color] = [:]
    private var texts: [TextKey: Kept] = [:]
    /// Titles and numbers come and go with the issues, so past this many the texts start over.
    private let limit = 6000

    func color(_ ink: CardInk, look: Look, in context: GraphicsContext) -> Color {
        let key = ColorKey(ink: ink, look: look)
        lock.lock()
        defer { lock.unlock() }
        if let color = colors[key] { return color }
        let color = Color(ink.color.resolve(in: context.environment))
        colors[key] = color
        return color
    }

    func text(_ text: CardText, look: Look, in context: GraphicsContext) -> Kept {
        let key = TextKey(text: text, look: look)
        lock.lock()
        defer { lock.unlock() }
        if let kept = texts[key] { return kept }
        let resolved = context.resolve(text.text)
        let kept = Kept(text: resolved, width: text.room.map { resolved.measure(in: $0).width } ?? 0)
        if texts.count >= limit { texts.removeAll(keepingCapacity: true) }
        texts[key] = kept
        return kept
    }

    /// Starts over, as a test does to paint a card from nothing.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        colors.removeAll()
        texts.removeAll()
    }
}

/// A colour a card is painted with, named so that it can be kept once worked out.
enum CardInk: Hashable {
    case card, cardHover, cardLifted, selectionFill
    case cardBorder, cardHoverBorder, cardLiftedBorder, selectionBorder
    case partHover, textSecondary, textTertiary, textBody, barOff, urgent, epic, treeLine
    case milestone(MilestoneMark)
    case label(hex: String)
    case option(String)

    var color: Color {
        switch self {
        case .card: Theme.card
        case .cardHover: Theme.cardHover
        case .cardLifted: Theme.cardLifted
        case .selectionFill: Theme.selectionFill
        case .cardBorder: Theme.cardBorder
        case .cardHoverBorder: Theme.cardHoverBorder
        case .cardLiftedBorder: Theme.cardLiftedBorder
        case .selectionBorder: Theme.selectionBorder
        case .partHover: Theme.partHover
        case .textSecondary: Theme.textSecondary
        case .textTertiary: Theme.textTertiary
        case .textBody: Theme.textBody
        case .barOff: Theme.barOff
        case .urgent: Theme.urgent
        case .epic: Theme.epic
        case .treeLine: Theme.treeLine
        case .milestone(let mark): mark.color
        case .label(let hex): Theme.labelColor(hex)
        case .option(let name): Theme.optionColor(name) ?? Theme.textTertiary
        }
    }
}

/// A text on a card, named by what it shows so that it can be kept once resolved.
enum CardText: Hashable {
    case number(String, lifted: Bool)
    case parent(number: Int, title: String?, epic: Bool)
    case title(String)
    case due(String, DueTone)
    /// The flag of a blocked issue, with the blocker's number once it is known.
    case blocker(String?)
    case label(String)
    case moreLabels(Int)
    case progress(done: Int, of: Int)
    /// A milestone or a field's value.
    case chip(String)
    case initials(String)
    case symbol(Symbol)

    enum Symbol: Hashable {
        case pullRequest, iteration, date, textField, urgent
    }

    var text: Text {
        switch self {
        case .number(let number, let lifted):
            Text(number).font(.system(size: CardView.metaSize)).monospacedDigit()
                .foregroundStyle(lifted ? Theme.textSecondary : Theme.textTertiary)
        case .parent(let number, let title, let epic):
            // An epic is named by its icon and title, like a project in Linear; another parent by its number.
            (epic ? Text(title ?? "#\(number)") : Text("\(Image(systemName: "arrow.turn.left.up")) #\(number) \(title ?? "")"))
                .font(.system(size: CardView.metaSize)).foregroundStyle(Theme.textTertiary)
        case .title(let title):
            Text(title).font(.system(size: CardView.titleSize, weight: .medium)).foregroundStyle(Theme.text)
        case .due(let label, let tone):
            Text("\(Image(systemName: "calendar")) \(label)").font(.system(size: CardView.chipSize)).foregroundStyle(tone.color)
        case .blocker(let blocker):
            (blocker.map { Text("\(Image(systemName: "flag.fill")) \($0)").font(.system(size: CardView.chipSize)).monospacedDigit() }
                ?? Text(Image(systemName: "flag.fill")).font(.system(size: CardView.chipSize - 2, weight: .medium)))
                .foregroundStyle(Theme.blocked)
        case .label(let name):
            Text(name).font(.system(size: CardView.chipSize, weight: .medium)).foregroundStyle(Theme.textBody)
        case .moreLabels(let count):
            Text("+\(count)").font(.system(size: CardView.chipSize)).foregroundStyle(Theme.textSecondary)
        case .progress(let done, let total):
            Text("\(done)/\(total)").font(.system(size: CardView.chipSize)).monospacedDigit().foregroundStyle(Theme.textSecondary)
        case .chip(let value):
            Text(value).font(.system(size: CardView.chipSize)).foregroundStyle(Theme.textSecondary)
        case .initials(let initials):
            Text(initials).font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: 0x111214))
        case .symbol(.pullRequest):
            Text(Image(systemName: "arrow.triangle.pull")).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textTertiary)
        case .symbol(.iteration):
            Text(Image(systemName: "arrow.triangle.2.circlepath")).font(.system(size: CardView.chipSize - 3, weight: .semibold)).foregroundStyle(Theme.textTertiary)
        case .symbol(.date):
            Text(Image(systemName: "calendar")).font(.system(size: CardView.chipSize - 2)).foregroundStyle(Theme.textTertiary)
        case .symbol(.textField):
            Text(Image(systemName: "text.alignleft")).font(.system(size: CardView.chipSize - 3)).foregroundStyle(Theme.textTertiary)
        case .symbol(.urgent):
            Text("!").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.onColor)
        }
    }

    /// The room the painter measures it in; nil for texts drawn without being measured.
    var room: CGSize? {
        switch self {
        case .number, .due, .progress: CGSize(width: 200, height: 40)
        case .blocker(let blocker): blocker == nil ? nil : CGSize(width: 200, height: 40)
        case .parent: CGSize(width: 600, height: 40)
        case .label, .chip: CGSize(width: 400, height: 40)
        case .moreLabels: CGSize(width: 100, height: 40)
        case .title, .initials, .symbol: nil
        }
    }
}

private struct CardPainter {
    var context: GraphicsContext
    var size: CGSize
    var titleHeight: CGFloat
    private let look: CardPaintCache.Look

    init(context: GraphicsContext, size: CGSize, titleHeight: CGFloat) {
        self.context = context
        self.size = size
        self.titleHeight = titleHeight
        look = CardPaintCache.Look(context.environment)
    }

    private func ink(_ ink: CardInk) -> Color {
        CardPaintCache.shared.color(ink, look: look, in: context)
    }

    private func text(_ text: CardText) -> CardPaintCache.Kept {
        CardPaintCache.shared.text(text, look: look, in: context)
    }

    func draw(_ view: CardView) {
        let card = view.card
        let item = card.item
        let padding = CardView.padding
        var parts: [(kind: PickerKind, rect: CGRect)] = []
        var fold: CGRect?
        var numberRect: CGRect?
        // Each part lights up in a shape that suits it, as in Linear: a small square behind an icon, a halo
        // around avatars, and chips in their own outline.
        func hovered(_ kind: PickerKind) -> Bool { view.hoveredPart == kind && !view.lifted }
        func part(_ kind: PickerKind, _ rect: CGRect) {
            parts.append((kind, rect))
        }
        if view.slotHeight != nil {
            drawSlot()
            return
        }
        // Behind the card: the lines from its parent, then the card under it.
        if let tree = view.tree { drawTree(tree, edge: view.stackEdge) }
        if view.stackEdge { drawStackEdge() }
        defer { if !view.lifted { CardRegionStore.shared.set(item.id, parts, fold: fold, number: numberRect) } }
        let outline = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: CardView.cornerRadius, style: .continuous)
        let fill = ink(view.lifted ? .cardLifted : view.selected ? .selectionFill : (view.highlighted ? .cardHover : .card))
        let border = ink(view.lifted ? .cardLiftedBorder : view.selected ? .selectionBorder : (view.highlighted ? .cardHoverBorder : .cardBorder))
        context.fill(outline, with: .color(fill))
        context.stroke(outline, with: .color(border), lineWidth: view.selected && !view.lifted ? 1.5 : 1)

        // Top line: the arrow that folds the sub-issues under the card, number, pull-request mark, the parent of a
        // sub-issue whose parent is elsewhere, and assignees on the right. A board belongs to one project, so the
        // repository is left to the number's tooltip.
        let topY = padding.height + 9
        var x = padding.width
        if card.nested != nil {
            let rect = CGRect(x: x - 3, y: topY - 7, width: 14, height: 14)
            fold = rect
            if view.hoveringFold, !view.lifted {
                context.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 5), with: .color(ink(.partHover)))
            }
            context.stroke(
                Self.foldArrow(folded: card.folded, center: CGPoint(x: rect.midX, y: rect.midY)),
                with: .color(ink(.textSecondary)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            x = rect.maxX + 5
        }
        let number = text(.number(item.displayNumber, lifted: view.lifted))
        context.draw(number.text, at: CGPoint(x: x, y: topY), anchor: .leading)
        numberRect = CGRect(x: x, y: topY - 8, width: number.width, height: 16)
        x += number.width + 6
        if item.kind == .pullRequest {
            context.draw(text(.symbol(.pullRequest)).text, at: CGPoint(x: x, y: topY), anchor: .leading)
            x += 16
        }
        if card.showsParent, let parentNumber = item.parentNumber {
            let avatars = item.kind == .draft ? 0 : 18 + CGFloat(max(min(item.assignees.count, 3), 1) - 1) * 13
            let room = size.width - padding.width - avatars - 10 - x
            let label = text(.parent(number: parentNumber, title: item.parentTitle, epic: card.parentIsEpic))
            let icon: CGFloat = card.parentIsEpic ? 15 : 0
            let width = min(label.width, room - 12 - icon)
            if width >= 48 {
                let rect = CGRect(x: x - 2, y: topY - 9, width: width + 12 + icon, height: 18)
                let kind: PickerKind = card.parentIsEpic ? .epic : .parent
                part(kind, rect)
                if hovered(kind) { chip(rect, hovered: true) }
                if card.parentIsEpic {
                    context.stroke(
                        PlanningGlyph.layers(in: CGRect(x: rect.minX + 5, y: topY - 6, width: 12, height: 12)), with: .color(ink(.epic)),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )
                }
                context.draw(label.text, in: CGRect(x: rect.minX + 6 + icon, y: topY - 8, width: width, height: 16))
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
                avatarRing = ink(.partHover)
                context.fill(Path(roundedRect: halo, cornerRadius: halo.height / 2), with: .color(avatarRing))
                if item.assignees.isEmpty { drawUnassigned(in: rect) }
            }
        }
        drawAvatars(item.assignees, rightEdge: size.width - padding.width, midY: topY, ring: avatarRing)

        // Title, wrapped to at most three lines.
        let titleRect = CGRect(x: padding.width, y: padding.height + 18 + 6, width: size.width - 2 * padding.width, height: titleHeight)
        context.draw(text(.title(item.title)).text, in: titleRect)

        // Bottom line: priority, labels, sub-issue progress.
        let bottomY = titleRect.maxY + 6 + 10
        x = padding.width
        if card.showsPriority {
            let rect = CGRect(x: x, y: bottomY - 7, width: 14, height: 14)
            part(.priority, rect)
            if hovered(.priority) {
                context.fill(Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 5), with: .color(ink(.partHover)))
            }
            drawPriority(card.priority, x: x, midY: bottomY)
            x += 14 + 6
        }
        // The due date comes last but always shows, so labels make room for it.
        let dueChip = card.due.map { due in text(.due(due.label, due.tone)) }
        let limit = size.width - padding.width - (dueChip.map { $0.width + 14 + 6 } ?? 0)
        // Blocked by an open issue: a red flag with the issue to finish first, before the labels, so they never push
        // it off the card.
        if let blocker = card.blocker {
            // Until this device knows which issue blocks it, the flag shows alone.
            let flag = text(.blocker(blocker.text))
            let width = blocker.text == nil ? 26 : flag.width + 14
            let rect = CGRect(x: x, y: bottomY - 10, width: width, height: 20)
            part(.blockedBy, rect)
            chip(rect, hovered: hovered(.blockedBy))
            context.draw(flag.text, at: CGPoint(x: rect.midX, y: bottomY), anchor: .center)
            x = rect.maxX + 6
        }
        var shown = 0
        // Labels are measured first, so the highlight can sit behind all of them.
        var labelLayout: [(label: LabelRef, text: GraphicsContext.ResolvedText, rect: CGRect)] = []
        var labelX = x
        for label in item.labels.prefix(2) {
            let name = text(.label(label.name))
            let width = name.width + 7 + 7 + 5 + 7
            guard labelX + width <= limit else { break }
            labelLayout.append((label, name.text, CGRect(x: labelX, y: bottomY - 10, width: width, height: 20)))
            labelX += width + 6
        }
        if item.kind != .draft, let first = labelLayout.first, let last = labelLayout.last {
            part(.labels, first.rect.union(last.rect))
        }
        for (label, name, rect) in labelLayout {
            let color = ink(.label(hex: label.color))
            let capsule = Path(roundedRect: rect, cornerRadius: rect.height / 2)
            context.fill(capsule, with: .color(color.opacity(hovered(.labels) ? 0.24 : 0.14)))
            context.fill(Path(ellipseIn: CGRect(x: rect.minX + 7, y: bottomY - 3.5, width: 7, height: 7)), with: .color(color))
            context.draw(name, at: CGPoint(x: rect.minX + 19, y: bottomY), anchor: .leading)
            x = rect.maxX + 6
            shown += 1
        }
        if item.labels.count > shown, shown > 0 {
            let more = text(.moreLabels(item.labels.count - shown))
            let width = more.width + 14
            if x + width <= limit {
                let rect = CGRect(x: x, y: bottomY - 10, width: width, height: 20)
                chip(rect)
                context.draw(more.text, at: CGPoint(x: rect.minX + 7, y: bottomY), anchor: .leading)
                x = rect.maxX + 6
            }
        }
        if item.subTotal > 0 {
            let progress = text(.progress(done: item.subCompleted, of: item.subTotal))
            let width = progress.width + 7 + 11 + 4 + 7
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
                context.stroke(glyph, with: .color(ink(.textSecondary)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                context.stroke(
                    Path(ellipseIn: CGRect(x: origin.x + 6.2, y: origin.y + 5.8, width: 3.1, height: 3.1)),
                    with: .color(ink(.textSecondary)), lineWidth: 1.2
                )
                context.draw(progress.text, at: CGPoint(x: rect.minX + 7 + 11 + 4, y: bottomY), anchor: .leading)
                x = rect.maxX + 6
            }
        }
        if let dueChip {
            let rect = CGRect(x: x, y: bottomY - 10, width: dueChip.width + 14, height: 20)
            part(.dueDate, rect)
            chip(rect, hovered: hovered(.dueDate))
            context.draw(dueChip.text, at: CGPoint(x: rect.minX + 7, y: bottomY), anchor: .leading)
            x = rect.maxX + 6
        }
        // The milestone last: it is the same for many cards, so it gives way to what tells them apart.
        if let milestone = card.milestone {
            let name = text(.chip(milestone))
            let textWidth = min(name.width, 110)
            let width = 7 + 10 + 5 + textWidth + 7
            if x + width <= size.width - padding.width {
                let rect = CGRect(x: x, y: bottomY - 10, width: width, height: 20)
                part(.milestone, rect)
                chip(rect, hovered: hovered(.milestone))
                let diamond = CGRect(x: rect.minX + 7, y: bottomY - 5, width: 10, height: 10)
                let outline = PlanningGlyph.diamond(in: diamond, inset: 1.1)
                let color = ink(.milestone(card.milestoneMark))
                switch card.milestoneMark {
                case .completed:
                    context.fill(outline, with: .color(color))
                case .current, .late:
                    context.stroke(outline, with: .color(color), lineWidth: 1.3)
                    context.fill(PlanningGlyph.diamond(in: diamond, inset: 3.4), with: .color(color))
                case .upcoming, .none:
                    context.stroke(outline, with: .color(color), lineWidth: 1.3)
                }
                context.draw(name.text, in: CGRect(x: rect.minX + 7 + 10 + 5, y: bottomY - 8, width: textWidth, height: 16))
                x = rect.maxX + 6
            }
        }
        // The project's own fields the view shows, after everything else, as far as there is room.
        for field in card.chips {
            let value = text(.chip(field.text))
            let textWidth = min(value.width, 110)
            let width = 7 + 10 + 5 + textWidth + 7
            guard x + width <= size.width - padding.width else { break }
            let rect = CGRect(x: x, y: bottomY - 10, width: width, height: 20)
            chip(rect)
            let icon = CGRect(x: rect.minX + 7, y: bottomY - 5, width: 10, height: 10)
            let center = CGPoint(x: icon.midX, y: icon.midY)
            switch field.icon {
            case .option(let color):
                context.fill(Path(ellipseIn: icon.insetBy(dx: 1.5, dy: 1.5)), with: .color(ink(.option(color))))
            case .iteration:
                context.draw(text(.symbol(.iteration)).text, at: center, anchor: .center)
            case .date:
                context.draw(text(.symbol(.date)).text, at: center, anchor: .center)
            case .text:
                context.draw(text(.symbol(.textField)).text, at: center, anchor: .center)
            }
            context.draw(value.text, in: CGRect(x: rect.minX + 7 + 10 + 5, y: bottomY - 8, width: textWidth, height: 16))
            x = rect.maxX + 6
        }
    }

    /// What `CardStackEdge` draws behind a card: a second card's edge, 6 points in on each side and 5 points lower.
    private func drawStackEdge() {
        let rect = CGRect(x: 6, y: CardStackEdge.height, width: size.width - 12, height: size.height)
        let shape = RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous)
        context.fill(shape.path(in: rect), with: .color(ink(.card)))
        context.stroke(shape.inset(by: 0.5).path(in: rect), with: .color(ink(.cardBorder)), lineWidth: 1)
    }

    /// What `CardTreeLines` draws in the gutter left of a sub-issue card and through the gap above it.
    private func drawTree(_ place: Nesting.Place, edge: Bool) {
        let gutter = CGFloat(min(place.depth, CardTreeLines.deepest)) * CardTreeLines.indent
        let gap = CardTreeLines.boardGap
        let height = gap + size.height + (edge ? CardStackEdge.height : 0)
        var lines = context
        lines.translateBy(x: -gutter, y: -gap)
        lines.stroke(CardTreeLines.path(place: place, gap: gap, branchY: 19, height: height), with: .color(ink(.treeLine)), lineWidth: 1)
    }

    /// Where the card being dragged would land: a dashed card as big as the lifted one.
    private func drawSlot() {
        let path = RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous).path(in: CGRect(origin: .zero, size: size))
        context.fill(path, with: .color(Theme.accent.opacity(0.10)))
        context.stroke(path, with: .color(Theme.accent.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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

    /// The quiet parts of a card (due date, sub-issues, milestone, fields) are text with a symbol, as Reminders
    /// writes them; under the pointer they light up as the button they are.
    private func chip(_ rect: CGRect, hovered: Bool = false) {
        guard hovered else { return }
        context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(ink(.partHover)))
    }

    /// Where an avatar would be: a dashed circle, shown when pointing at an unassigned issue's avatar spot.
    private func drawUnassigned(in rect: CGRect) {
        let circle = CGRect(x: rect.maxX - 18, y: rect.midY - 9, width: 18, height: 18).insetBy(dx: 1.5, dy: 1.5)
        context.stroke(Path(ellipseIn: circle), with: .color(ink(.textTertiary)), style: StrokeStyle(lineWidth: 1.2, dash: [2.2, 2]))
    }

    private func drawPriority(_ level: PriorityLevel, x: CGFloat, midY: CGFloat) {
        if level == .urgent {
            let rect = CGRect(x: x + 1, y: midY - 6, width: 12, height: 12)
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(ink(.urgent)))
            context.draw(text(.symbol(.urgent)).text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            return
        }
        let bars: [(CGFloat, Bool)] = [(4, level >= .low), (7, level >= .medium), (10, level >= .high)]
        for (index, bar) in bars.enumerated() {
            let rect = CGRect(x: x + CGFloat(index) * 5, y: midY + 6 - bar.0, width: 3, height: bar.0)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(ink(bar.1 ? .textBody : .barOff)))
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
                context.draw(text(.initials(String(person.login.prefix(2)).uppercased())).text, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
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
    /// The gap between cards in a column of the Mac board.
    static let boardGap: CGFloat = 8

    var place: Nesting.Place
    /// The gap between cards, which the lines bridge.
    var gap: CGFloat
    /// Where the branch meets the card, from the card's top: beside its first line.
    var branchY: CGFloat = 19

    var body: some View {
        Canvas { context, size in
            context.stroke(Self.path(place: place, gap: gap, branchY: branchY, height: size.height), with: .color(Theme.treeLine), lineWidth: 1)
        }
        .padding(.top, -gap)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The lines for a card's place, from the bottom of the card above, `height` tall in all.
    static func path(place: Nesting.Place, gap: CGFloat, branchY: CGFloat, height: CGFloat) -> Path {
        let depth = min(place.depth, Self.deepest)
        var path = Path()
        for level in 0..<depth {
            let lineX = CGFloat(level) * Self.indent + Self.indent / 2
            let continues = place.continues.indices.contains(level) && place.continues[level]
            if level < depth - 1 {
                if continues {
                    path.move(to: CGPoint(x: lineX, y: 0))
                    path.addLine(to: CGPoint(x: lineX, y: height))
                }
                continue
            }
            let y = gap + branchY
            let end = CGFloat(depth) * Self.indent
            if continues {
                path.move(to: CGPoint(x: lineX, y: 0))
                path.addLine(to: CGPoint(x: lineX, y: height))
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
        return path
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
        .background(RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous).fill(Theme.cardLifted))
        .overlay(RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous).strokeBorder(Theme.cardLiftedBorder, lineWidth: 1))
        .background(alignment: .top) { CardStackEdge() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.epicGroupSpoken(epic: group.epic.title, count: group.count)))
    }
}

struct CardStackEdge: View {
    static let height: CGFloat = 5

    var body: some View {
        RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous)
            .fill(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .padding(.horizontal, 6)
            .offset(y: Self.height)
            .accessibilityHidden(true)
    }
}
