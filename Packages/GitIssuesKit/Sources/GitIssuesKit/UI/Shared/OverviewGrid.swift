import SwiftUI

// MARK: - Layout

/// Where the overview's cards stand: as many columns as fit cards of a readable width, every card the same size, so
/// that two rows of them fill the window. On iPhone, where cards stand one under another, each is as tall as its
/// fullest page needs, up to a few rows.
struct OverviewGridLayout: Equatable {
    struct Metrics: Equatable {
        var minCardWidth: CGFloat
        var maxColumns: Int
        var gap: CGFloat
        var margin: CGFloat
        var top: CGFloat
        var bottom: CGFloat
        /// The card's name, with its pages' icons.
        var header: CGFloat
        var row: CGFloat
        /// Below the last row of a page.
        var pageBottom: CGFloat
        var minCardHeight: CGFloat
        var maxCardHeight: CGFloat
        /// At most this many rows to a card, whatever room there is, and no more than its pages need: on iPhone, where
        /// cards stand one under another.
        var fixedRows: Int? = nil

        #if os(macOS)
        static let standard = Metrics(
            minCardWidth: 320, maxColumns: 4, gap: 16, margin: 20, top: 8, bottom: 24,
            header: 46, row: 30, pageBottom: 10, minCardHeight: 250, maxCardHeight: 560
        )
        #else
        static let regular = Metrics(
            minCardWidth: 340, maxColumns: 3, gap: 16, margin: 20, top: 8, bottom: 24,
            header: 56, row: 44, pageBottom: 8, minCardHeight: 300, maxCardHeight: 640
        )
        static let compact = Metrics(
            minCardWidth: 280, maxColumns: 1, gap: 14, margin: 16, top: 6, bottom: 24,
            header: 56, row: 44, pageBottom: 6, minCardHeight: 0, maxCardHeight: .infinity, fixedRows: 6
        )
        #endif
    }

    let metrics: Metrics
    let count: Int
    let columns: Int
    /// The size of every card, or with `heights` the largest.
    let card: CGSize
    /// Each card's own height, on iPhone.
    let heights: [CGFloat]?

    /// `rowsNeeded`: how many rows each card's fullest page has, for cards that are only as tall as that.
    init(width: CGFloat, height: CGFloat, count: Int, metrics: Metrics, rowsNeeded: [Int]? = nil) {
        self.metrics = metrics
        self.count = count
        let inner = max(width - 2 * metrics.margin, 200)
        columns = max(1, min(metrics.maxColumns, Int((inner + metrics.gap) / (metrics.minCardWidth + metrics.gap))))
        let cardWidth = ((inner - metrics.gap * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
        let cardHeight: CGFloat
        if let rows = metrics.fixedRows {
            cardHeight = metrics.header + metrics.row * CGFloat(rows) + metrics.pageBottom
        } else {
            let rowsOfCards = max(1, (count + columns - 1) / columns)
            let onScreen = CGFloat(min(2, rowsOfCards))
            let room = height - metrics.top - metrics.bottom - metrics.gap * (onScreen - 1)
            cardHeight = min(max((room / onScreen).rounded(.down), metrics.minCardHeight), metrics.maxCardHeight)
        }
        card = CGSize(width: cardWidth, height: cardHeight)
        if let rows = metrics.fixedRows, let needed = rowsNeeded, needed.count == count {
            heights = needed.map { metrics.header + metrics.row * CGFloat(min(rows, max(1, $0))) + metrics.pageBottom }
        } else {
            heights = nil
        }
    }

    func size(_ index: Int) -> CGSize {
        CGSize(width: card.width, height: heights.map { $0[min(max(index, 0), $0.count - 1)] } ?? card.height)
    }

    /// How many issues the card at `index` has room for on a page.
    func rows(_ index: Int) -> Int {
        max(1, Int((size(index).height - metrics.header - metrics.pageBottom) / metrics.row))
    }

    /// The top left corner of the card at `index`.
    func origin(_ index: Int) -> CGPoint {
        if let heights {
            return CGPoint(x: metrics.margin, y: metrics.top + heights.prefix(index).reduce(0, +) + CGFloat(index) * metrics.gap)
        }
        return CGPoint(
            x: metrics.margin + CGFloat(index % columns) * (card.width + metrics.gap),
            y: metrics.top + CGFloat(index / columns) * (card.height + metrics.gap)
        )
    }

    var contentHeight: CGFloat {
        if let heights {
            return metrics.top + heights.reduce(0, +) + CGFloat(max(0, count - 1)) * metrics.gap + metrics.bottom
        }
        let rows = max(1, (count + columns - 1) / columns)
        return metrics.top + CGFloat(rows) * card.height + CGFloat(rows - 1) * metrics.gap + metrics.bottom
    }

    /// The place whose card's middle is nearest `center`: where a card being dragged would go.
    func nearestIndex(to center: CGPoint) -> Int {
        guard count > 0 else { return 0 }
        return (0..<count).min { a, b in
            distance(center, a) < distance(center, b)
        } ?? 0
    }

    private func distance(_ point: CGPoint, _ index: Int) -> CGFloat {
        let corner = origin(index)
        return hypot(corner.x + card.width / 2 - point.x, corner.y + card.height / 2 - point.y)
    }

    /// How many issues a page has room for, the last of them giving way to "N more" when there are more.
    var rowsPerPage: Int {
        max(1, Int((card.height - metrics.header - metrics.pageBottom) / metrics.row))
    }
}

// MARK: - Pages

/// What a page of a card holds, whichever card it is: its name and icon, its issues and how they show.
struct OverviewPage: Identifiable, Equatable {
    enum Icon: Equatable {
        case status(StatusGlyph)
        case symbol(String, Color)
    }

    enum Lead: Equatable {
        case status
        case priority
        case project
    }

    var key: String
    var title: String
    var icon: Icon
    var items: [Item]
    var lead: Lead
    /// In progress and Needs you: rows say how long an issue has waited.
    var showsIdle = false
    /// Done this week: rows say when.
    var finished = false
    /// Where "N more" leads: the project, if the page belongs to one.
    var projectId: String?
    var place: String

    var id: String { key }
    var count: Int { items.count }
    var label: String { String(localized: .overviewPageLabel(column: title, count: count)) }
}

extension AppModel {
    /// A card's pages, as it shows them.
    func overviewPages(of cardId: String) -> [OverviewPage] {
        if MineSmartCard(id: cardId) == .needsYou {
            return needsYouPages.map { page in
                OverviewPage(
                    key: page.key, title: page.reason.title, icon: .symbol(page.reason.systemImage, page.reason.color),
                    items: page.entries.map(\.item), lead: .project, showsIdle: true,
                    projectId: nil, place: MineSmartCard.needsYou.title
                )
            }
        }
        guard let lane = lane(cardId) else { return [] }
        return shownColumns(of: lane).map { column in
            let icon: StatusGlyph = switch column.key {
            case MineColumn.doneKey: Self.statusGlyph(.completed)
            case MineColumn.noBoardKey: .noProject
            case MineColumn.noStatusKey: .none
            default: glyph(projectId: lane.projectId, optionId: column.optionId)
            }
            return OverviewPage(
                key: column.key, title: column.title, icon: .status(icon), items: column.items,
                lead: column.kind == nil || column.key == MineColumn.doneKey ? .status : .priority,
                showsIdle: column.kind == .started, finished: column.key == MineColumn.doneKey,
                projectId: lane.projectId, place: lane.title
            )
        }
    }

    /// The key of the page a card shows.
    func currentPageKey(of cardId: String) -> String? {
        if MineSmartCard(id: cardId) == .needsYou { return currentNeedsYouPage?.key }
        return lane(cardId).flatMap(currentColumn(of:))?.key
    }
}

// MARK: - The grid

/// My Issues as an overview: a card per project, and Needs you, all the same size. A card pages sideways through the
/// columns of its board that Display shows; its name stays at the top with the page under it, and the icons at the
/// right turn to another page. On the Mac a card is dragged by its name: it lifts and follows the pointer, a slot
/// shows where it will land and the others make room.
struct OverviewGrid: View {
    @Environment(AppModel.self) private var model
    let metrics: OverviewGridLayout.Metrics
    /// What comes above the cards and scrolls with them, as My Issues' filter on iPhone and iPad.
    var header: AnyView? = nil

    #if os(macOS)
    @State private var scroll = ScrollPosition()
    /// How far the overview is scrolled from its top, how much of it shows, and how far it can scroll.
    @State private var scrolled = ScrollMetrics()

    struct ScrollMetrics: Equatable {
        var y: CGFloat = 0
        var visible: CGFloat = 0
        var maximum: CGFloat = 0
    }
    #endif

    var body: some View {
        GeometryReader { geometry in
            let drag = model.overviewDrag
            let cards = drag.order ?? model.overviewCards
            let layout = OverviewGridLayout(
                width: geometry.size.width, height: geometry.size.height, count: cards.count, metrics: metrics,
                rowsNeeded: metrics.fixedRows == nil ? nil : cards.map { id in
                    // A card that says it has nothing needs two rows for that.
                    model.overviewPages(of: id).map(\.count).max() ?? 2
                }
            )
            ScrollView {
                VStack(spacing: 0) {
                    header
                    ZStack(alignment: .topLeading) {
                        if let lifted = drag.liftedId, let index = cards.firstIndex(of: lifted) {
                            // Where the lifted card will land.
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.cardBehind)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Theme.cardBorder.opacity(0.6), lineWidth: 1)
                                )
                                .frame(width: layout.size(index).width, height: layout.size(index).height)
                                .offset(x: layout.origin(index).x, y: layout.origin(index).y)
                                .transition(.opacity)
                        }
                        ForEach(cards, id: \.self) { id in
                            let index = cards.firstIndex(of: id) ?? 0
                            let lifted = drag.liftedId == id
                            let origin = lifted ? drag.position : layout.origin(index)
                            OverviewCard(id: id, size: layout.size(index), rows: layout.rows(index), metrics: metrics, lifted: lifted, cards: cards)
                                .offset(x: origin.x, y: origin.y)
                                .zIndex(lifted ? 2 : drag.settlingId == id ? 1 : 0)
                                #if os(macOS)
                                .environment(\.overviewCardDragger, OverviewCardDragger(
                                    changed: { translation in follow(id, translation, layout: layout, cards: cards) },
                                    ended: { drop(layout: layout) }
                                ))
                                #endif
                        }
                    }
                    .frame(width: geometry.size.width, height: layout.contentHeight, alignment: .topLeading)
                }
            }
            #if os(macOS)
            .scrollPosition($scroll)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                // Measured from the top of the cards, under the toolbar the overview runs beneath.
                let visible = geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
                return ScrollMetrics(
                    y: geometry.contentOffset.y + geometry.contentInsets.top, visible: visible,
                    maximum: max(0, geometry.contentSize.height - visible)
                )
            } action: { _, metrics in
                let change = metrics.y - scrolled.y
                scrolled = metrics
                // A card being dragged stays under the pointer while the overview scrolls under it.
                if drag.liftedId != nil, change != 0 { drag.scrolled += change; retarget(layout: layout) }
            }
            .onChange(of: drag.translation) { _, _ in retarget(layout: layout) }
            #endif
            .onAppear { model.setOverviewRowsPerPage(layout.rowsPerPage) }
            .onChange(of: layout.rowsPerPage) { _, rows in model.setOverviewRowsPerPage(rows) }
        }
    }

    #if os(macOS)
    // MARK: Dragging a card

    /// The pointer moved with a card held by its name: the card follows, and the others make room where it would land.
    private func follow(_ id: String, _ translation: CGSize, layout: OverviewGridLayout, cards: [String]) {
        let drag = model.overviewDrag
        guard !drag.cancelled else { return }
        if drag.liftedId == nil {
            guard let index = cards.firstIndex(of: id) else { return }
            drag.lift(id, order: cards, from: layout.origin(index))
        }
        drag.translation = translation
        autoscroll(layout: layout)
    }

    /// Where the card held would land now, and the others moving out of its way.
    private func retarget(layout: OverviewGridLayout) {
        let drag = model.overviewDrag
        guard let id = drag.liftedId, var order = drag.order, let from = order.firstIndex(of: id) else { return }
        let center = CGPoint(x: drag.position.x + layout.card.width / 2, y: drag.position.y + layout.card.height / 2)
        let target = layout.nearestIndex(to: center)
        guard target != from else { return }
        order.remove(at: from)
        order.insert(id, at: min(target, order.count))
        withAnimation(Theme.spring) { drag.order = order }
    }

    /// Near the top or bottom of the window, the overview scrolls on by itself while a card is held there by its name.
    private func autoscroll(layout: OverviewGridLayout) {
        let drag = model.overviewDrag
        // Where the pointer holds the card: about the middle of its name.
        let pointer = drag.position.y + layout.metrics.header / 2 - scrolled.y
        let edge: CGFloat = 44
        var step: CGFloat = 0
        if pointer < edge { step = -14 } else if pointer > scrolled.visible - edge { step = 14 }
        drag.autoscroll = step
        guard step != 0, !drag.autoscrolling, scrolled.maximum > 0 else { return }
        drag.autoscrolling = true
        Task { @MainActor in
            while drag.liftedId != nil, drag.autoscroll != 0 {
                let y = min(max(scrolled.y + drag.autoscroll, 0), scrolled.maximum)
                if y == scrolled.y { break }
                scroll.scrollTo(y: y)
                try? await Task.sleep(for: .milliseconds(16))
            }
            drag.autoscrolling = false
        }
    }

    /// Letting go: the card settles into its slot, and the overview keeps the order from now on.
    private func drop(layout: OverviewGridLayout) {
        let drag = model.overviewDrag
        defer { drag.cancelled = false }
        guard let id = drag.liftedId, let order = drag.order, !drag.cancelled else { return }
        let index = order.firstIndex(of: id) ?? 0
        drag.settlingId = id
        withAnimation(Theme.spring) {
            model.moveCard(id, toShownIndex: index)
            drag.end()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if drag.settlingId == id { drag.settlingId = nil }
        }
    }

    #endif
}

/// A card held by its name on the Mac: which, where it is, the order the overview would have if it were let go now.
@MainActor
@Observable
final class OverviewCardDrag {
    private(set) var liftedId: String?
    /// The cards in the order they show while one is held; nil otherwise.
    var order: [String]?
    var translation: CGSize = .zero
    /// How far the overview has scrolled since the card was lifted.
    var scrolled: CGFloat = 0
    /// The card that was just let go, still above the others while it settles.
    var settlingId: String?
    /// Esc put the card back; the rest of that drag is ignored.
    var cancelled = false
    @ObservationIgnored private var start: CGPoint = .zero
    @ObservationIgnored var autoscroll: CGFloat = 0
    @ObservationIgnored var autoscrolling = false

    /// The top left corner of the card held, in the overview.
    var position: CGPoint {
        CGPoint(x: start.x + translation.width, y: start.y + translation.height + scrolled)
    }

    func lift(_ id: String, order: [String], from origin: CGPoint) {
        liftedId = id
        self.order = order
        start = origin
        translation = .zero
        scrolled = 0
        #if os(macOS)
        watchEscape()
        #endif
    }

    #if os(macOS)
    @ObservationIgnored private var escapeWatch: Timer?

    /// While the mouse is held, AppKit hands the app nothing but the mouse until it is let go, so a press of Esc would
    /// only arrive after the drop. The key's state is read instead, also when the pointer rests.
    private func watchEscape() {
        escapeWatch?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.liftedId != nil else { return }
                // Held down now, or pressed and waiting behind the mouse in the queue.
                var pressed = CGEventSource.keyState(.combinedSessionState, key: 53)
                if !pressed, let waiting = NSApp.nextEvent(matching: .keyDown, until: .distantPast, inMode: .eventTracking, dequeue: false),
                   waiting.keyCode == 53 {
                    _ = NSApp.nextEvent(matching: .keyDown, until: .distantPast, inMode: .eventTracking, dequeue: true)
                    pressed = true
                }
                if pressed { withAnimation(Theme.spring) { self.cancel() } }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        escapeWatch = timer
    }
    #endif

    /// Esc: the card goes back where it was, and the rest of the drag is ignored.
    func cancel() {
        guard let id = liftedId else { return }
        cancelled = true
        settlingId = id
        end()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if settlingId == id { settlingId = nil }
        }
    }

    func end() {
        #if os(macOS)
        escapeWatch?.invalidate()
        escapeWatch = nil
        #endif
        liftedId = nil
        order = nil
        translation = .zero
        scrolled = 0
        autoscroll = 0
    }
}

#if os(macOS)
/// How a card's name reports a drag to the grid.
struct OverviewCardDragger {
    var changed: (CGSize) -> Void = { _ in }
    var ended: () -> Void = {}
}

private struct OverviewCardDraggerKey: EnvironmentKey {
    static let defaultValue = OverviewCardDragger()
}

extension EnvironmentValues {
    var overviewCardDragger: OverviewCardDragger {
        get { self[OverviewCardDraggerKey.self] }
        set { self[OverviewCardDraggerKey.self] = newValue }
    }
}

#endif

// MARK: - A card

/// One card: its name and the page it shows, the icons of its other pages at the right; then the page, which
/// swipes sideways to the next.
struct OverviewCard: View {
    @Environment(AppModel.self) private var model
    let id: String
    let size: CGSize
    /// How many issues a page has room for.
    let rows: Int
    let metrics: OverviewGridLayout.Metrics
    let lifted: Bool
    /// The cards in their order, for VoiceOver's Move Earlier and Move Later.
    let cards: [String]
    @State private var pageKey: String?

    var body: some View {
        let pages = model.overviewPages(of: id)
        let current = model.currentPageKey(of: id)
        let page = pages.first { $0.key == current } ?? pages.first
        VStack(alignment: .leading, spacing: 0) {
            OverviewCardHeader(id: id, pages: pages, page: page) { key in
                withAnimation(Theme.spring) { pageKey = key }
                model.showPage(key, of: id)
            }
            .frame(height: metrics.header)
            if pages.isEmpty {
                OverviewCardEmpty(id: id)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(pages) { page in
                            OverviewPageView(page: page, rows: rows, metrics: metrics)
                                .frame(width: size.width, alignment: .topLeading)
                                .id(page.key)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $pageKey)
                .scrollIndicators(.never)
                .onAppear { pageKey = current }
                .onChange(of: current) { _, key in
                    if pageKey != key { withAnimation(Theme.spring) { pageKey = key } }
                }
                .onChange(of: pageKey) { _, key in
                    if let key, key != current { model.showPage(key, of: id) }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.card)
                .shadow(color: lifted ? Theme.cardLiftedShadow : Theme.cardShadow, radius: lifted ? 28 : 2, y: lifted ? 16 : 1)
                .shadow(color: lifted ? Theme.cardRaisedShadow : .clear, radius: lifted ? 4 : 0, y: lifted ? 2 : 0)
        )
        .scaleEffect(lifted ? 1.03 : 1)
        .animation(Theme.spring, value: lifted)
        #if os(macOS)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            model.overviewCardFrames[id] = frame
        }
        .onDisappear { model.overviewCardFrames[id] = nil }
        #endif
        .modifier(OverviewCardMenu(id: id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.cardTitle(id)))
        .accessibilityIdentifier("card-\(model.cardTitle(id))")
        .accessibilityAction(named: Text(.overviewMoveEarlier)) { move(-1) }
        .accessibilityAction(named: Text(.overviewMoveLater)) { move(1) }
    }

    private func move(_ delta: Int) {
        guard let index = cards.firstIndex(of: id) else { return }
        let target = index + delta
        guard target >= 0, target < cards.count else { return }
        withAnimation(Theme.spring) { model.moveCard(id, toShownIndex: target) }
    }
}

/// The card's name with the page it shows under it, and an icon for each page at the right: the one shown on a soft
/// fill, the others a click away. On the Mac the name is where a card is taken hold of to move it.
private struct OverviewCardHeader: View {
    @Environment(AppModel.self) private var model
    #if os(macOS)
    @Environment(\.overviewCardDragger) private var dragger
    #endif
    let id: String
    let pages: [OverviewPage]
    let page: OverviewPage?
    let turn: (String) -> Void

    var body: some View {
        let lane = model.lane(id)
        HStack(spacing: 9) {
            icon(lane)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.cardTitle(id))
                    .font(.uiSemibold)
                    .foregroundStyle(Theme.text)
                if let page {
                    Text(verbatim: "\(page.title) · \(page.count)")
                        .font(.tiny)
                        .foregroundStyle(Theme.textTertiary)
                        .contentTransition(.numericText())
                }
            }
            .lineLimit(1)
            .layoutPriority(1)
            Spacer(minLength: 6)
            if pages.count > 1 {
                HStack(spacing: 1) {
                    ForEach(pages) { item in
                        PageButton(page: item, shown: item.key == page?.key) { turn(item.key) }
                            .modifier(OverviewPageDrop(cardId: id, pageKey: item.key))
                    }
                }
                .fixedSize()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .contentShape(Rectangle())
        #if os(macOS)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in dragger.changed(value.translation) }
                .onEnded { _ in dragger.ended() }
        )
        #endif
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func icon(_ lane: MineLane?) -> some View {
        if MineSmartCard(id: id) == .needsYou {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.urgent)
                .frame(width: 20, height: 20)
        } else if let projectId = lane?.projectId ?? (id.hasPrefix("project/") ? String(id.dropFirst(8)) : nil) {
            ProjectTile(projectId: projectId, size: 20)
        } else {
            StatusIcon(glyph: .noProject, size: 18)
                .frame(width: 20, height: 20)
        }
    }
}

/// A page's icon at the top right of a card.
private struct PageButton: View {
    let page: OverviewPage
    let shown: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                switch page.icon {
                case .status(let glyph):
                    StatusIcon(glyph: glyph, size: 13)
                case .symbol(let name, let color):
                    Image(systemName: name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(color)
                }
            }
            .frame(width: Self.size, height: Self.size)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(shown ? Theme.cardPageShown : hovering ? Theme.cardRowHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(page.label)
        .accessibilityLabel(page.label)
        .accessibilityAddTraits(shown ? .isSelected : [])
    }

    #if os(macOS)
    static let size: CGFloat = 24
    #else
    static let size: CGFloat = 32
    #endif
}

/// A card none of whose columns Display shows has issues of yours: it says so, and how many wait in the others.
private struct OverviewCardEmpty: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        let lane = model.lane(id)
        let hidden = lane.map { $0.open.count } ?? 0
        VStack(spacing: 4) {
            Text(MineSmartCard(id: id) == .needsYou ? .nothingNeedsYou : .overviewNothingShown)
                .font(.uiMedium)
                .foregroundStyle(Theme.textSecondary)
            if hidden > 0 {
                Text(.overviewHiddenColumns(count: hidden))
                    .font(.small)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}

/// A page: its issues, as many as fit, and how many more there are.
private struct OverviewPageView: View {
    let page: OverviewPage
    let rows: Int
    let metrics: OverviewGridLayout.Metrics

    var body: some View {
        let shown = page.items.count > rows ? Array(page.items.prefix(rows - 1)) : page.items
        let more = page.items.count - shown.count
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { item in
                OverviewRow(item: item, page: page)
                    .frame(height: metrics.row)
            }
            if more > 0 {
                OverviewMoreButton(page: page, count: more)
                    .frame(height: metrics.row)
            }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - A row

/// What a row of a card says: the issue's priority, status or project, its number and title, and what needs saying at
/// the end: who blocks it, how long it has waited and when it is due, or when it was finished. On Needs you the page
/// says why the issue is there, and the due date or the days idle how much.
struct OverviewRowLabel: View {
    @Environment(AppModel.self) private var model
    let item: Item
    let page: OverviewPage
    var selected = false

    var body: some View {
        HStack(spacing: 8) {
            switch page.lead {
            case .status:
                StatusIcon(glyph: model.glyph(of: item))
            case .priority:
                PriorityIcon(level: model.priorityLevel(of: item))
            case .project:
                if let projectId = item.projectId {
                    ProjectIcon(projectId: projectId, size: 13)
                } else {
                    StatusIcon(glyph: .noProject, size: 13)
                }
            }
            Text(item.displayNumber)
                .font(.small)
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white.opacity(0.8) : Theme.textTertiary)
                .lineLimit(1)
                .fixedSize()
            Text(item.title)
                .font(.uiMedium)
                .foregroundStyle(selected ? Color.white : Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if page.finished {
            if let date = item.closedAt ?? MineRules.lastChange(of: item) {
                Text(CalendarDay(date).shortLabel())
                    .font(.small)
                    .foregroundStyle(selected ? Color.white.opacity(0.88) : Theme.textTertiary)
                    .fixedSize()
            }
        } else {
            OverviewRowSignals(item: item, showsIdle: page.showsIdle, selected: selected)
        }
    }
}

/// At the end of a row: who blocks it, how long it has waited, when it is due. The title keeps the rest of the room,
/// so a sub-issue's progress and labels stay on the issue's page.
struct OverviewRowSignals: View {
    @Environment(AppModel.self) private var model
    let item: Item
    let showsIdle: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let blocker = model.blockerMark(for: item) {
                BlockerFlag(mark: blocker, size: 12)
            }
            if showsIdle, let days = model.idleDays(of: item) {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 10, weight: .medium))
                    Text(.overviewIdle(days: days))
                }
                .font(.small)
                .help(Text(.overviewIdleTooltip(days: days)))
            }
            if let due = model.dueBadge(for: item) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .medium))
                    Text(due.label)
                }
                .font(.small)
                .foregroundStyle(selected ? Color.white : due.tone.color)
                .help(due.tooltip)
            }
        }
        .foregroundStyle(selected ? Color.white.opacity(0.88) : Theme.textSecondary)
        .lineLimit(1)
        .fixedSize()
    }
}

/// "39 more in Notebook" at the end of a page: a click shows the project; on Needs you and the issues on no board it
/// only counts.
private struct OverviewMoreButton: View {
    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.openRoute) private var openRoute
    #endif
    let page: OverviewPage
    let count: Int

    var body: some View {
        if let projectId = page.projectId {
            Button {
                #if os(macOS)
                model.select(.project(projectId))
                #else
                openRoute(.project(projectId))
                #endif
            } label: {
                Text(.overviewMoreIn(count: count, place: page.place))
                    .font(.smallMedium)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(.overviewMoreCount(count: count))
                .font(.smallMedium)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
