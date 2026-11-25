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
    /// The cards it stands on, for its sub-issues while they don't hang under it (`CardStackEdge`).
    var stack: Int { CardStackEdge.layers(of: item, nested: nested, folded: folded) }
    /// A sub-issue whose parent is in another column names the parent.
    var showsParent = false
    /// Whether that parent is an epic, which it then names with the epic's icon.
    var parentIsEpic = false
    /// The milestone it is planned for, on boards that aren't a milestone's.
    var milestone: String?
    var milestoneMark: MilestoneMark = .upcoming
    /// Whether its type opens the picker that changes it.
    var changesType = false
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
            changesType: canHaveIssueType(item),
            chips: chips,
            spokenChips: chips.map(spokenChip)
        )
    }
}

extension Nesting {
    /// How many cards the issue's card stands on here for its sub-issues (`CardStackEdge`).
    func stack(of item: Item) -> Int {
        CardStackEdge.layers(of: item, nested: nestedCounts[item.id], folded: folded.contains(item.id))
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
    /// The issue open in the peek.
    var peeked = false
    var lifted = false
    /// Changes when avatar images finish loading, so cards repaint with them.
    var avatarVersion = 0
    /// The clickable part under the pointer, drawn with a soft highlight.
    var hoveredPart: PickerKind? = nil
    /// Whether the pointer is on the arrow that folds the sub-issues under the card.
    var hoveringFold = false
    /// On the Mac board, what the column draws around a card, painted in the card's own pass so a row of a long
    /// column is a single view: the dashed slot where the lifted card would land, this tall, in place of the card;
    /// the cards a card with sub-issues stands on, this many (`CardStackEdge`); and the lines from a sub-issue's parent,
    /// in the gutter left of the card and through the gap above it. They reach past the card's frame, as the views
    /// they replace did, so the Canvas is that much bigger than the card it lays out as.
    var slotHeight: CGFloat? = nil
    var stack = 0
    var tree: Nesting.Place? = nil

    /// Room inside the card's edge, at its sides and above its first line: little, so that a title has room, and the
    /// avatars come about as close to the top edge as the priority to the bottom one.
    static let padding = CGSize(width: 10, height: 8)
    /// Under the last line, less than above the first: that line is as tall as the highlight of its chips, which its
    /// texts and marks sit in the middle of. So they keep about as far from the bottom edge as from the sides, and the
    /// chips' highlight as far from it as the avatars' halo from the top edge.
    static let bottomPadding: CGFloat = 5
    /// How far apart the parts of the bottom line are, from what one shows to what the next one shows: the same after
    /// the priority as between tags, dates and the milestone. Each of those lights up in a capsule `LabelMark.inset`
    /// wider than it on either side, and the capsules are what is laid out.
    static let partGap: CGFloat = 16
    static let chipSpacing = partGap - 2 * LabelMark.inset
    /// The middle of a card's first line, where the number and the people are, and where the line from its parent meets
    /// a sub-issue's card.
    static let firstLineY = padding.height + 9
    /// Rounder than a button, as Reminders' cards and Apple's grouped rows are.
    static let cornerRadius: CGFloat = 12
    /// A card stands on the board on a soft shadow rather than inside a border, and on a deeper one under the pointer.
    static let shadow = (radius: CGFloat(1.5), y: CGFloat(0.75))
    static let raisedShadow = (radius: CGFloat(2.5), y: CGFloat(1.5))
    /// How far the shadows reach past the card, which the Canvas makes room for: no further, as the room is part of
    /// every card's layer. With room for a wider shadow, a long column took a millisecond longer per scroll step, and
    /// so did growing the room for the card under the pointer, which cards scrolling under it keep changing. A board
    /// column leaves this much room beside its cards, or its scroll view would cut the shadow off.
    static let shadowRoom = EdgeInsets(top: 2, leading: 4, bottom: 5, trailing: 4)
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
        "\(card.item.displayNumber) \(card.item.title)"
            + (card.item.shownType.map { ", " + String(localized: .issueTypeTooltip(type: $0.name)) } ?? "")
            + (card.spokenBlocker.map { ", \($0)" } ?? "")
            + (card.due.map { ", \($0.tooltip)" } ?? "")
            + (card.item.parentNumber.map { number in
                ", " + String(localized: card.parentIsEpic
                    ? .epicTooltip(epic: card.item.parentTitle ?? "#\(number)") : .subIssueOf(number: "#\(number)"))
            } ?? "")
            + card.spokenChips.map { ", \($0)" }.joined()
    }

    static func height(titleHeight: CGFloat) -> CGFloat {
        padding.height + 18 + 6 + titleHeight + 6 + 20 + bottomPadding
    }

    /// How far the Canvas, which clips, reaches past the card for what is drawn around it: its shadow, the gutter and
    /// the gap above for the lines from a parent, and the cards under it with their own shadows; for the slot, its
    /// dashes, which straddle its outline. A lifted card has the shadow of the lift instead. The card lays out at its
    /// own size all the same.
    private var surroundings: (leading: CGFloat, top: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        guard slotHeight == nil else { return (1, 1, 1, 1) }
        let room = lifted ? EdgeInsets() : Self.shadowRoom
        let gutter = tree.map { CGFloat(min($0.depth, CardTreeLines.deepest)) * CardTreeLines.indent } ?? 0
        return (
            max(gutter, room.leading), max(tree == nil ? 0 : CardTreeLines.boardGap, room.top),
            stack > 0 ? CardStackEdge.height(stack) + Self.shadowRoom.bottom : room.bottom, room.trailing
        )
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

    /// A text ready to draw, and how wide and tall it is where the painter measures it.
    struct Kept {
        var text: GraphicsContext.ResolvedText
        var width: CGFloat
        var height: CGFloat
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
        let size = text.room.map { resolved.measure(in: $0) } ?? .zero
        let kept = Kept(text: resolved, width: size.width, height: size.height)
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
    case card, cardHover, cardLifted, selectionFill, peekFill
    /// A card a card stands on, 1 for the first under it.
    case cardBehind(Int)
    case cardShadow, cardRaisedShadow, cardOutline, selectionBorder, peekRing
    case partHover, textSecondary, textTertiary, textBody, barOff, urgent, treeLine
    case milestone(MilestoneMark)
    case label(hex: String)
    case option(String)

    var color: Color {
        switch self {
        case .card: Theme.card
        case .cardHover: Theme.cardHover
        case .cardLifted: Theme.cardLifted
        case .selectionFill: Theme.selectionFill
        case .peekFill: Theme.peekGround()
        case .cardBehind(let depth): Theme.cardBehind(depth)
        case .cardShadow: Theme.cardShadow
        case .cardRaisedShadow: Theme.cardRaisedShadow
        case .cardOutline: Theme.cardLiftedBorder
        case .selectionBorder: Theme.selectionBorder
        case .peekRing: Theme.peekRing()
        case .partHover: Theme.partHover
        case .textSecondary: Theme.textSecondary
        case .textTertiary: Theme.textTertiary
        case .textBody: Theme.textBody
        case .barOff: Theme.barOff
        case .urgent: Theme.urgent
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
            Text(name).font(.system(size: CardView.chipSize)).foregroundStyle(Theme.textSecondary)
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
            Marks.urgentMark.foregroundStyle(Theme.onColor)
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
        // Behind the card: the lines from its parent, then the cards under it.
        if let tree = view.tree { drawTree(tree, below: CardStackEdge.height(view.stack)) }
        if view.stack > 0 { drawStack(view.stack) }
        defer { if !view.lifted { CardRegionStore.shared.set(item.id, parts, fold: fold, number: numberRect) } }
        let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: CardView.cornerRadius, style: .continuous)
        let fill = ink(view.lifted ? .cardLifted : view.selected ? .selectionFill : view.peeked ? .peekFill : (view.highlighted ? .cardHover : .card))
        if view.lifted {
            context.fill(shape, with: .color(fill))
        } else {
            // No border: the card stands on a soft shadow, and seems to rise under the pointer and in the peek.
            let raised = view.highlighted || view.peeked
            let shadow = raised ? CardView.raisedShadow : CardView.shadow
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: ink(raised ? .cardRaisedShadow : .cardShadow), radius: shadow.radius, y: shadow.y))
                layer.fill(shape, with: .color(fill))
            }
        }
        if view.peeked && !view.lifted {
            // The ground is the card's own, already under its shadow, and a picked card keeps its tint.
            context.draw(Marks.peek(in: CGRect(origin: .zero, size: size), cornerRadius: CardView.cornerRadius), mark: ink(.peekRing))
        } else if view.selected && !view.lifted {
            let ring = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75), cornerRadius: CardView.cornerRadius - 0.75, style: .continuous)
            context.stroke(ring, with: .color(ink(.selectionBorder)), lineWidth: 1.5)
        } else if look.contrast == .increased {
            // With Increase Contrast on, a shadow is too faint an edge: the card gets its outline back, as controls do.
            let outline = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: CardView.cornerRadius - 0.5, style: .continuous)
            context.stroke(outline, with: .color(ink(.cardOutline)), lineWidth: 1)
        }

        // Top line: the arrow that folds the sub-issues under the card, number, pull-request mark, the parent of a
        // sub-issue whose parent is elsewhere, and assignees on the right. A board belongs to one project, so the
        // repository is left to the number's tooltip.
        let topY = CardView.firstLineY
        var x = padding.width
        if card.nested != nil {
            let rect = CGRect(x: x - 3, y: topY - 7, width: 14, height: 14)
            fold = rect
            if view.hoveringFold, !view.lifted {
                context.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 5), with: .color(ink(.partHover)))
            }
            context.draw(Marks.foldArrow(folded: card.folded, center: CGPoint(x: rect.midX, y: rect.midY)), mark: ink(.textSecondary))
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
                // In the grey of the epic's name: the epic's own colour is for its header and the roadmap.
                if card.parentIsEpic {
                    context.stroke(
                        PlanningGlyph.layers(in: CGRect(x: rect.minX + 5, y: topY - 6, width: 12, height: 12)), with: .color(ink(.textTertiary)),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )
                }
                draw(label, x: rect.minX + 6 + icon, midY: topY, width: width)
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
            // Its bars end a point inside its box, and the part after it starts its capsule's inset before what it shows.
            x += 13 + CardView.partGap - LabelMark.inset
        }
        // A part that starts the line moves out by its padding, so that what it shows lines up with the title and
        // only its highlight reaches past.
        func start(_ x: CGFloat) -> CGFloat { x == padding.width ? x - LabelMark.inset : x }
        // The due date comes last but always shows, so labels make room for it.
        let dueChip = card.due.map { due in text(.due(due.label, due.tone)) }
        let spacing = CardView.chipSpacing
        let limit = size.width - padding.width - (dueChip.map { $0.width + 14 + spacing } ?? 0)
        // Blocked by an open issue: a red flag with the issue to finish first, before the labels, so they never push
        // it off the card.
        if let blocker = card.blocker {
            // Until this device knows which issue blocks it, the flag shows alone.
            let flag = text(.blocker(blocker.text))
            let width = blocker.text == nil ? 26 : flag.width + 14
            let rect = CGRect(x: start(x), y: bottomY - 10, width: width, height: 20)
            part(.blockedBy, rect)
            chip(rect, hovered: hovered(.blockedBy))
            context.draw(flag.text, at: CGPoint(x: rect.midX, y: bottomY), anchor: .center)
            x = rect.maxX + spacing
        }
        // Labels are measured first, so the highlight can sit behind all of them.
        var labelLayout: [(label: LabelRef, text: GraphicsContext.ResolvedText, rect: CGRect)] = []
        var labelX = start(x)
        let labels = item.shownLabels
        // The type stands first of them and takes one of the card's places for tags, so that a card with a type is no
        // busier than one without: it stays when labels have to give way.
        var typeLayout: (color: String?, text: CardPaintCache.Kept, textWidth: CGFloat, rect: CGRect)?
        if let type = item.shownType {
            let name = text(.label(type.name))
            let width = IssueTypeMark.width(name: name.width)
            if labelX + width <= limit {
                let textWidth = min(name.width, IssueTypeMark.longestName)
                typeLayout = (type.color, name, textWidth, CGRect(x: labelX, y: bottomY - 10, width: width, height: IssueTypeMark.height))
                labelX += width + spacing
            }
        }
        for label in labels.prefix(LabelMark.onCard - (typeLayout == nil ? 0 : 1)) {
            let name = text(.label(label.name))
            let width = LabelMark.width(name: name.width)
            guard labelX + width <= limit else { break }
            labelLayout.append((label, name.text, CGRect(x: labelX, y: bottomY - 10, width: width, height: LabelMark.height)))
            labelX += width + spacing
        }
        // "+2" for the labels that don't fit, when it fits itself: part of the labels, which it opens too.
        var moreLayout: (text: GraphicsContext.ResolvedText, rect: CGRect)?
        if let last = labelLayout.last?.rect ?? typeLayout?.rect, labels.count > labelLayout.count {
            let more = text(.moreLabels(labels.count - labelLayout.count))
            let rect = CGRect(x: last.maxX + spacing, y: bottomY - 10, width: LabelMark.inset + more.width + LabelMark.inset, height: LabelMark.height)
            if rect.maxX <= limit { moreLayout = (more.text, rect) }
        }
        if let typeLayout {
            let rect = typeLayout.rect
            if card.changesType {
                part(.issueType, rect)
                chip(rect, hovered: hovered(.issueType))
            }
            let square = CGRect(
                x: rect.minX + IssueTypeMark.inset, y: bottomY - IssueTypeMark.square / 2,
                width: IssueTypeMark.square, height: IssueTypeMark.square
            )
            context.draw(Marks.issueType(in: square), mark: ink(.option(typeLayout.color ?? "GRAY")))
            draw(typeLayout.text, x: square.maxX + IssueTypeMark.gap, midY: bottomY, width: typeLayout.textWidth)
            x = rect.maxX + spacing
        }
        if item.kind != .draft, let tags = labelLayout.first.map({ first in
            first.rect.union(moreLayout?.rect ?? labelLayout[labelLayout.count - 1].rect)
        }) ?? moreLayout?.rect {
            part(.labels, tags)
            chip(tags, hovered: hovered(.labels))
        }
        // A label is a dot in its colour and its name, as Reminders writes its tags, rather than a tinted pill: a
        // board of pills is a board of coloured blobs.
        for (label, name, rect) in labelLayout {
            let dot = CGRect(x: rect.minX + LabelMark.inset, y: bottomY - LabelMark.dot / 2, width: LabelMark.dot, height: LabelMark.dot)
            context.fill(Path(ellipseIn: dot), with: .color(ink(.label(hex: label.color))))
            context.draw(name, at: CGPoint(x: dot.maxX + LabelMark.gap, y: bottomY), anchor: .leading)
            x = rect.maxX + spacing
        }
        if let moreLayout {
            context.draw(moreLayout.text, at: CGPoint(x: moreLayout.rect.minX + LabelMark.inset, y: bottomY), anchor: .leading)
            x = moreLayout.rect.maxX + spacing
        }
        if item.subTotal > 0 {
            let progress = text(.progress(done: item.subCompleted, of: item.subTotal))
            let width = progress.width + 7 + 11 + 4 + 7
            if start(x) + width <= limit {
                let rect = CGRect(x: start(x), y: bottomY - 10, width: width, height: 20)
                part(.subIssues, rect)
                chip(rect, hovered: hovered(.subIssues))
                context.draw(Marks.subIssue(in: CGRect(x: rect.minX + 7, y: bottomY - 5.5, width: 11, height: 11)), mark: ink(.textSecondary))
                context.draw(progress.text, at: CGPoint(x: rect.minX + 7 + 11 + 4, y: bottomY), anchor: .leading)
                x = rect.maxX + spacing
            }
        }
        if let dueChip {
            let rect = CGRect(x: start(x), y: bottomY - 10, width: dueChip.width + 14, height: 20)
            part(.dueDate, rect)
            chip(rect, hovered: hovered(.dueDate))
            context.draw(dueChip.text, at: CGPoint(x: rect.minX + 7, y: bottomY), anchor: .leading)
            x = rect.maxX + spacing
        }
        // The milestone last: it is the same for many cards, so it gives way to what tells them apart.
        if let milestone = card.milestone {
            let name = text(.chip(milestone))
            let textWidth = min(name.width, 110)
            let width = 7 + 10 + 5 + textWidth + 7
            if start(x) + width <= size.width - padding.width {
                let rect = CGRect(x: start(x), y: bottomY - 10, width: width, height: 20)
                part(.milestone, rect)
                chip(rect, hovered: hovered(.milestone))
                // Grey, as the same milestone repeats down the board; its shape still tells the current one, and only
                // a milestone past its date keeps its colour (`MilestoneMark.quietColor`).
                let diamond = CGRect(x: rect.minX + 7, y: bottomY - 5, width: 10, height: 10)
                context.draw(Marks.milestone(card.milestoneMark, in: diamond), mark: ink(card.milestoneMark == .late ? .milestone(.late) : .textTertiary))
                draw(name, x: rect.minX + 7 + 10 + 5, midY: bottomY, width: textWidth)
                x = rect.maxX + spacing
            }
        }
        // The project's own fields the view shows, after everything else, as far as there is room.
        for field in card.chips {
            let value = text(.chip(field.text))
            let textWidth = min(value.width, 110)
            let width = 7 + 10 + 5 + textWidth + 7
            guard start(x) + width <= size.width - padding.width else { break }
            let rect = CGRect(x: start(x), y: bottomY - 10, width: width, height: 20)
            // An iteration opens its picker, as the milestone does.
            let kind: PickerKind? = field.icon == .iteration ? .iteration(fieldId: field.fieldId) : nil
            if let kind { part(kind, rect) }
            chip(rect, hovered: kind.map(hovered) ?? false)
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
            draw(value, x: rect.minX + 7 + 10 + 5, midY: bottomY, width: textWidth)
            x = rect.maxX + spacing
        }
    }

    /// What `CardStackEdge` draws behind a card: the cards it stands on, the furthest back first, each on its own shadow.
    private func drawStack(_ layers: Int) {
        for card in CardStackEdge.cards(behind: size, layers: layers).reversed() {
            let shape = RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous).path(in: card.rect)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: ink(.cardShadow), radius: CardView.shadow.radius, y: CardView.shadow.y))
                layer.fill(shape, with: .color(ink(.cardBehind(card.depth))))
            }
        }
    }

    /// What `CardTreeLines` draws in the gutter left of a sub-issue card and through the gap above it, down past the
    /// cards it stands on, `below` tall.
    private func drawTree(_ place: Nesting.Place, below: CGFloat) {
        let gutter = CGFloat(min(place.depth, CardTreeLines.deepest)) * CardTreeLines.indent
        let gap = CardTreeLines.boardGap
        let height = gap + size.height + below
        var lines = context
        lines.translateBy(x: -gutter, y: -gap)
        lines.stroke(CardTreeLines.path(place: place, gap: gap, branchY: CardView.firstLineY, height: height), with: .color(ink(.treeLine)), lineWidth: 1)
    }

    /// Where the card being dragged would land: a dashed card as big as the lifted one.
    private func drawSlot() {
        let path = RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous).path(in: CGRect(origin: .zero, size: size))
        context.fill(path, with: .color(Theme.accent.opacity(0.10)))
        context.stroke(path, with: .color(Theme.accent.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    /// A text cut short to `width`, centred on `midY` as a text drawn at a point is: one drawn into a box starts at the
    /// box's top, which put names about a point above the labels' and dates' beside them.
    private func draw(_ kept: CardPaintCache.Kept, x: CGFloat, midY: CGFloat, width: CGFloat) {
        // A little taller than the line, so that rounding never leaves it no room; it starts at the top all the same.
        context.draw(kept.text, in: CGRect(x: x, y: midY - kept.height / 2, width: width, height: kept.height + 2))
    }

    /// The quiet parts of a card (labels, due date, sub-issues, milestone, fields) are text with a symbol, as
    /// Reminders writes them; under the pointer they light up as the button they are.
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
        // The bars stand on the bottom of their box, 10 points tall in a box of 12: a point higher, they are centred on
        // the line, as the capitals of the texts beside them are. Urgent's square is centred in the box.
        let box = CGRect(x: x, y: midY - 6 - (level == .urgent ? 0 : 1), width: 14, height: 12)
        context.draw(Marks.priority(level, in: box), mark: ink(level == .urgent ? .urgent : .textBody), off: ink(.barOff))
        if level == .urgent {
            let square = Marks.urgentSquare(in: box)
            context.draw(text(.symbol(.urgent)).text, at: CGPoint(x: square.midX, y: square.midY), anchor: .center)
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
    var branchY: CGFloat = CardView.firstLineY

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
        Marks.treeLines(
            place, deepest: Self.deepest, lineX: { CGFloat($0) * Self.indent + Self.indent / 2 },
            branchY: gap + branchY, branchEnd: CGFloat(min(place.depth, Self.deepest)) * Self.indent, height: height
        )
    }
}

/// The issues standing together in a column under a header, an epic's or a parent's, while they are dragged by their
/// header to move them all: a card with the name, an epic's icon, and how many of its issues come along, on a card for
/// each of them (`CardStackEdge`).
struct GroupCard: View {
    var group: Nesting.Group
    var width: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // A parent's sub-issues come as the parent's card would, without an icon, as their header shows it.
            if group.kind == .epic {
                EpicIcon(size: CardView.lineHeight - 2)
                    .frame(height: CardView.lineHeight)
            }
            Text(group.head.title)
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
        .background(alignment: .top) { CardStackEdge(layers: CardStackEdge.layers(group.count)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(group.kind == .epic
            ? .epicGroupSpoken(epic: group.head.title, count: group.count)
            : .parentGroupSpoken(count: group.count, parent: group.head.title)))
    }
}

/// The cards a card stands on: one for each of its sub-issues while they don't hang under it in its column (folded
/// into it, or in other columns), and one for each issue it carries along in a drag, up to three. Each peeks out less
/// than the one in front of it and is narrower, as cards further back in a pile are, so that a single one is a small
/// detail and three read as many more behind them. A board card paints them itself (`CardView.stack`); this draws them
/// with views, behind a card it is the background of.
struct CardStackEdge: View {
    /// More issues than this stand on this many cards.
    static let deepest = 3
    /// How far each card peeks out under the one in front of it, and how far in it is on each side.
    private static let steps: [(peek: CGFloat, inset: CGFloat)] = [(4, 7), (3, 13), (2, 18)]

    /// One card of the pile: 1 for the one right under the card.
    struct Placed {
        var depth: Int
        var inset: CGFloat
        /// How far its bottom edge is below the card's.
        var below: CGFloat
    }

    var layers = 1

    /// How many cards a card that stands for this many issues stands on.
    static func layers(_ count: Int) -> Int {
        min(max(count, 0), deepest)
    }

    /// How many a card stands on for its sub-issues: none while some hang under it in its column (`nested`) unfolded,
    /// as they are in sight there.
    static func layers(of item: Item, nested: Int?, folded: Bool) -> Int {
        nested != nil && !folded ? 0 : layers(max(item.subTotal, nested ?? 0))
    }

    /// How far below the card the pile reaches. A column works it out for every card it lays out, so it is kept.
    static func height(_ layers: Int) -> CGFloat {
        heights[min(max(layers, 0), deepest)]
    }
    private static let heights = (0...deepest).map { placed($0).last?.below ?? 0 }

    static func placed(_ layers: Int) -> [Placed] {
        var below: CGFloat = 0
        return steps.prefix(max(layers, 0)).enumerated().map { index, step in
            below += step.peek
            return Placed(depth: index + 1, inset: step.inset, below: below)
        }
    }

    /// The cards behind one of this size, in its own coordinates, from the one right under it back.
    static func cards(behind size: CGSize, layers: Int) -> [(depth: Int, rect: CGRect)] {
        placed(layers).map { card in
            (card.depth, CGRect(x: card.inset, y: card.below, width: size.width - 2 * card.inset, height: size.height))
        }
    }

    var body: some View {
        ZStack {
            ForEach(Self.placed(layers).reversed(), id: \.depth) { card in
                RoundedRectangle(cornerRadius: CardView.cornerRadius, style: .continuous)
                    .fill(Theme.cardBehind(card.depth))
                    .shadow(color: Theme.cardShadow, radius: CardView.shadow.radius, y: CardView.shadow.y)
                    .padding(.horizontal, card.inset)
                    .offset(y: card.below)
            }
        }
        .accessibilityHidden(true)
    }
}

extension CardView {
    /// The deep shadow under a card lifted off a board or a list while it is dragged.
    static let liftedShadow = (radius: CGFloat(22), y: CGFloat(16))
}

extension View {
    /// The shadow of a card being dragged (`CardView.liftedShadow`), while it is lifted.
    func liftedShadow(_ lifted: Bool = true) -> some View {
        shadow(color: lifted ? Theme.shadow : .clear, radius: lifted ? CardView.liftedShadow.radius : 0, y: lifted ? CardView.liftedShadow.y : 0)
    }
}

/// The issue open in the peek (`Marks.peek`), behind the issue and as big as its shape, for what is drawn with views: an
/// issue in My Issues' overview, a line of a timeline. Cards and the list's rows paint the same mark themselves.
struct PeekMark: View {
    /// The corner radius of the issue's own shape.
    var cornerRadius: CGFloat
    /// On a picked row, which is filled with the accent.
    var onAccent = false

    var body: some View {
        Canvas { context, size in
            context.draw(
                Marks.peek(in: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius, onAccent: onAccent),
                mark: Theme.peekRing(onAccent: onAccent), off: Theme.peekGround(onAccent: onAccent)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An issue lit up to take the issues dragged onto it as its sub-issues (`Marks.nestTarget`), laid over the issue in
/// its own frame and reaching a little past it: a card on any board, a row of the Mac's list, an issue in My Issues'
/// overview, an epic's header.
struct NestTargetMark: View {
    /// The corner radius of the issue's own shape.
    var cornerRadius: CGFloat

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: Marks.nestOutset, dy: Marks.nestOutset)
            context.draw(Marks.nestTarget(around: rect, cornerRadius: cornerRadius), mark: Theme.accent, off: Theme.nestTint)
        }
        .padding(-Marks.nestOutset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
