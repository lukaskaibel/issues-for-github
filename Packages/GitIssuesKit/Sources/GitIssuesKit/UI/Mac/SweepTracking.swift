#if os(macOS)
import AppKit

/// ⌘-dragging over issues (`SweepPick`) on the Mac, wherever they are: the list's table, on its own page as on an
/// issue's, the board, My Issues' overview and the Inbox. One event monitor follows every such press: the SwiftUI parts
/// register what they show, as with right-click menus (`ContextMenus`), and a table says itself whether a press lands on
/// one of its issues. Once the pointer has moved a few points the press sweeps; let go before that, it was a ⌘-click,
/// which goes on to the view as it came. The press is followed event by event, never in a loop of its own, so that
/// SwiftUI draws the picks and scrolls as the pointer goes.
@MainActor
final class SweepAreas {
    static let shared = SweepAreas()

    /// Issues a sweep can pick. Points are in window coordinates with the origin at the top left, as SwiftUI's `.global`
    /// space.
    struct Area {
        var place: SweepPick.Place
        /// The issue a press at the point lands on, if a sweep can start there. A table answers for its own rows.
        var start: (CGPoint) -> String? = { _ in nil }
        /// The issues it can pick and where they are now, also those scrolled out of sight where it knows them.
        var rows: () -> [SweepRow]
        /// Cards side by side, as in columns, are swept by a rectangle; rows that reach across a list, by how far up or
        /// down the pointer is (false).
        var sideways = true
        /// Scrolls toward the pointer while it is at an edge, sixty times a second; nil when the sweep is over.
        var autoscroll: (CGPoint?) -> Void = { _ in }
    }

    /// How far the pointer moves before a press is a sweep rather than a click.
    static let threshold: CGFloat = 3

    private var areas: [UUID: Area] = [:]
    private var press: Press?
    /// The press handed back to the view after it turned out to be a click, which the monitor lets through then.
    private var replaying: TimeInterval?

    func register(_ id: UUID, _ area: Area) {
        areas[id] = area
    }

    func remove(_ id: UUID) {
        areas[id] = nil
    }

    #if DEBUG
    /// The issues of every registered area and where they are, for the debug remote.
    var debugRows: [SweepRow] {
        areas.values.flatMap { $0.rows() }
    }
    #endif

    /// Whether a press can start a sweep: the left button, once, with ⌘ and no other modifier.
    static func starts(_ event: NSEvent) -> Bool {
        event.type == .leftMouseDown && event.clickCount <= 1
            && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
    }

    /// A press, move or release of the left button, as the app gets it. Returns whether it was taken, so that nothing
    /// else sees it.
    func handle(_ event: NSEvent, model: AppModel) -> Bool {
        switch event.type {
        case .leftMouseDown:
            // A press whose release never came, as when a dialog took it.
            if let press {
                press.finish()
                self.press = nil
            }
            if let replaying, event.timestamp == replaying {
                self.replaying = nil
                return false
            }
            guard let press = Press(event, among: areas.values, model: model) else { return false }
            self.press = press
            return true
        case .leftMouseDragged:
            guard let press else { return false }
            press.moved(to: event.locationInWindow)
            return true
        case .leftMouseUp:
            guard let press else { return false }
            self.press = nil
            if press.sweeping {
                press.moved(to: event.locationInWindow)
                press.finish()
            } else {
                // A ⌘-click: handed back as it came, so that the view picks or opens as on any.
                replaying = press.down.timestamp
                press.window.postEvent(event, atStart: true)
                press.window.postEvent(press.down, atStart: true)
            }
            return true
        default:
            return false
        }
    }

    /// Escape: a sweep going on is called off, and what was picked before it is picked again. The button still has to
    /// come up. Returns whether there was one.
    func cancel() -> Bool {
        guard let press, press.sweeping else { return false }
        press.cancel()
        return true
    }

    // MARK: Scrolling

    /// How far in from a list's edge the pointer starts scrolling it: about the height of a row, so that it can still
    /// sweep up to the last row in sight without the list running off.
    static let edgeZone: CGFloat = 24

    /// Points to scroll each sixtieth of a second with the pointer `distance` inside the edge, or past it (negative):
    /// slowly near it, faster the further past it.
    static func speed(insideEdgeBy distance: CGFloat) -> CGFloat {
        guard distance < edgeZone else { return 0 }
        let strength = min(1, (edgeZone - distance) / (edgeZone * 4))
        return 2 + strength * 26
    }

    /// Scrolls `scrollView` up or down toward `point`, in the window's coordinates, while it is near or past its top or
    /// bottom edge, as a card held at a column's edge scrolls it.
    static func autoscroll(_ scrollView: NSScrollView, toward point: NSPoint) {
        let clip = scrollView.contentView
        guard let document = scrollView.documentView else { return }
        let local = clip.convert(point, from: nil)
        let insets = scrollView.contentInsets
        // The part of the clip view that shows, not what lies under the toolbar or under the room left at the end.
        let flipped = clip.isFlipped
        let top = flipped ? clip.bounds.minY + insets.top : clip.bounds.maxY - insets.top
        let bottom = flipped ? clip.bounds.maxY - insets.bottom : clip.bounds.minY + insets.bottom
        let fromTop = flipped ? local.y - top : top - local.y
        let fromBottom = flipped ? bottom - local.y : local.y - bottom
        var delta: CGFloat = 0
        if fromTop < edgeZone {
            delta = -speed(insideEdgeBy: fromTop)
        } else if fromBottom < edgeZone {
            delta = speed(insideEdgeBy: fromBottom)
        }
        guard delta != 0 else { return }
        // How far down the document shows, counted from its top whichever way the clip view counts.
        let height = document.frame.height
        let lowest = -insets.top
        let highest = max(lowest, height - clip.bounds.height + insets.bottom)
        var origin = clip.bounds.origin
        let current = flipped ? origin.y : height - clip.bounds.height - origin.y
        let next = min(max(current + delta, lowest), highest)
        guard next != current else { return }
        origin.y = flipped ? next : height - clip.bounds.height - next
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }
}

/// A press with ⌘ held on an issue, from the button going down to it coming up.
@MainActor
private final class Press {
    let down: NSEvent
    let window: NSWindow
    private let id: String
    private let area: SweepAreas.Area
    private weak var model: AppModel?
    private(set) var sweeping = false
    private var cancelled = false
    /// Where the pointer is, at the top left of the window's content: at rest it sends no moves.
    private var pointer: CGPoint
    /// Where the sweep started, which stays on its issue as the issues scroll.
    private var anchor: CGPoint
    private let offset: CGSize?
    private var timer: Timer?
    private let height: CGFloat

    init?(_ event: NSEvent, among areas: Dictionary<UUID, SweepAreas.Area>.Values, model: AppModel) {
        guard SweepAreas.starts(event), let window = event.window, window === model.mainWindow, model.overlay == nil,
              let content = window.contentView,
              let hit = window.contentView?.superview?.hitTest(event.locationInWindow),
              // On the toolbar over the page the press is the toolbar's.
              hit.isDescendant(of: content) else { return nil }
        let height = content.bounds.height
        let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
        var found: (area: SweepAreas.Area, id: String)?
        // A table under the press answers for its rows: the list's, or one on an issue's page.
        var view: NSView? = hit
        while let current = view, found == nil {
            if let table = current as? HoverTableView { found = table.sweepArea(pressedAt: event.locationInWindow) }
            view = current.superview
        }
        // On the peek, a notice or the selection bar over the board, the press is theirs.
        if found == nil, !ContextMenus.shared.isUnderFloatingView(point) {
            found = areas.lazy.compactMap { area in area.start(point).map { (area, $0) } }.first
        }
        guard let found else { return nil }
        down = event
        self.window = window
        self.height = height
        id = found.id
        area = found.area
        self.model = model
        pointer = point
        anchor = point
        offset = Self.pressed(found.id, in: found.area.rows(), near: point).map {
            CGSize(width: point.x - $0.minX, height: point.y - $0.minY)
        }
        // Its own press: one that can't become a peek, whichever of the app's monitors sees it first.
        model.deepPress.begin(at: NSEvent.mouseLocation, counts: false)
    }

    /// The row of the issue nearest to `point`: an issue can show twice, as in Needs you and on its project's card, or
    /// in the groups of both its assignees.
    private static func pressed(_ id: String, in rows: [SweepRow], near point: CGPoint) -> CGRect? {
        rows.filter { $0.id == id }.map(\.frame).min { a, b in
            hypot(a.midX - point.x, a.midY - point.y) < hypot(b.midX - point.x, b.midY - point.y)
        }
    }

    func moved(to location: NSPoint) {
        pointer = CGPoint(x: location.x, y: height - location.y)
        if !sweeping {
            guard hypot(pointer.x - anchor.x, pointer.y - anchor.y) > SweepAreas.threshold else { return }
            sweeping = true
            model?.beginSweep(on: id, in: area.place)
            // A pointer at rest sends no moves: the edges scroll from here, and what comes under it is swept.
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        sweep()
    }

    private func tick() {
        guard sweeping, !cancelled else { return }
        area.autoscroll(pointer)
        sweep()
    }

    private func sweep() {
        guard !cancelled, let model else { return }
        let rows = area.rows()
        if let offset, let frame = Self.pressed(id, in: rows, near: anchor) {
            anchor = CGPoint(x: frame.minX + offset.width, y: frame.minY + offset.height)
        }
        model.sweep(over: SweepPick.swept(rows, from: anchor, to: pointer, sideways: area.sideways))
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        stop()
        model?.cancelSweep()
    }

    /// The button is up, or the press is given up on.
    func finish() {
        stop()
        if sweeping, !cancelled { model?.endSweep() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if sweeping { area.autoscroll(nil) }
    }
}

/// Where the rows of a SwiftUI list are in the window, as each reports it, for sweeping over them. Only rows that are
/// built report: those on screen and a few around them. An issue can show on two rows, as in Needs you and on its
/// project's card, so each row reports for itself.
@MainActor
final class SweepRowFrames {
    private var frames: [UUID: SweepRow] = [:]

    /// `row` is the view reporting.
    func set(_ frame: CGRect, for id: String, row: UUID) {
        frames[row] = SweepRow(id: id, frame: frame)
    }

    func remove(row: UUID) {
        frames[row] = nil
    }

    func row(at point: CGPoint) -> String? {
        frames.values.first { $0.frame.contains(point) }?.id
    }

    var rows: [SweepRow] {
        Array(frames.values)
    }
}

extension AppModel {
    /// ⌘-drags over issues, wherever they are.
    func installSweepMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            let taken = MainActor.assumeIsolated { self.signedIn && SweepAreas.shared.handle(event, model: self) }
            return taken ? nil : event
        }
    }
}
#endif
