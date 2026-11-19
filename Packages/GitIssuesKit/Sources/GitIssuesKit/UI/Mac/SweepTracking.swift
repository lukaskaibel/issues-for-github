#if os(macOS)
import AppKit

/// Follows a press with ⌘ held on an issue until the button comes up. Once the pointer has moved a few points it sweeps
/// (`SweepPick`): the issues between where the press started and the pointer are picked as it goes, and while it rests
/// at an edge the issues scroll toward it. Let go before that, it was a ⌘-click, which the caller hands on to the view as
/// it came. Escape calls a sweep off.
@MainActor
struct SweepTracker {
    enum Outcome {
        case swept
        /// The press was a click; `up` is its mouse-up, taken from the queue.
        case click(up: NSEvent)
    }

    /// How far the pointer moves before a press is a sweep rather than a click.
    static let threshold: CGFloat = 3

    /// Whether a press can start a sweep: the left button, once, with ⌘ and no other modifier.
    static func starts(_ event: NSEvent) -> Bool {
        event.type == .leftMouseDown && event.clickCount <= 1
            && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
    }

    /// The issues swept with the pointer at `point`, in the window's coordinates.
    var swept: (_ point: NSPoint) -> Set<String>
    /// Scrolls toward the pointer while it rests at or past an edge; nil when the sweep is over.
    var autoscroll: (_ point: NSPoint?) -> Void = { _ in }

    func follow(_ down: NSEvent, on id: String, in place: SweepPick.Place, window: NSWindow, model: AppModel) -> Outcome {
        // Its own press: one that can't become a peek, whichever of the app's monitors sees it first.
        model.deepPress.begin(at: NSEvent.mouseLocation, counts: false)
        var sweeping = false
        var cancelled = false
        // Where the pointer is: a pointer at rest sends no moves, so it is where the last one left it.
        var pointer = down.locationInWindow
        defer {
            if sweeping {
                NSEvent.stopPeriodicEvents()
                autoscroll(nil)
                if !cancelled { model.endSweep() }
            }
        }
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .periodic, .keyDown]) {
            switch event.type {
            case .leftMouseDragged:
                let point = event.locationInWindow
                pointer = point
                if !sweeping {
                    guard hypot(point.x - down.locationInWindow.x, point.y - down.locationInWindow.y) > Self.threshold else { continue }
                    sweeping = true
                    model.beginSweep(on: id, in: place)
                    // A pointer at rest sends no moves: the edges scroll from these, and what comes under it is swept.
                    NSEvent.startPeriodicEvents(afterDelay: 0, withPeriod: 1.0 / 60)
                }
                if !cancelled { model.sweep(over: swept(point)) }
            case .periodic:
                guard sweeping, !cancelled else { continue }
                autoscroll(pointer)
                model.sweep(over: swept(pointer))
            case .keyDown:
                // Escape: what was picked before is picked again. The button still has to come up.
                if event.keyCode == 53, sweeping, !cancelled {
                    cancelled = true
                    model.cancelSweep()
                    autoscroll(nil)
                }
            case .leftMouseUp:
                guard sweeping else { return .click(up: event) }
                if !cancelled { model.sweep(over: swept(event.locationInWindow)) }
                return .swept
            default:
                break
            }
        }
        return .swept
    }

    /// How far in from a list's edge the pointer starts scrolling it: about the height of a row, so that it can still
    /// sweep up to the last row on screen without the list running off.
    static let edgeZone: CGFloat = 24

    /// Points to scroll each sixtieth of a second with the pointer `distance` inside the edge, or past it (negative):
    /// slowly near it, faster the further past it.
    static func speed(insideEdgeBy distance: CGFloat) -> CGFloat {
        guard distance < edgeZone else { return 0 }
        let strength = min(1, (edgeZone - distance) / (edgeZone * 4))
        return 2 + strength * 26
    }

    /// Scrolls `scrollView` toward `point`, in the window's coordinates, while it is near or past its top or bottom edge,
    /// faster the further out, as a card held at a column's edge scrolls it. Returns whether it scrolled.
    @discardableResult
    static func autoscroll(_ scrollView: NSScrollView, toward point: NSPoint) -> Bool {
        let clip = scrollView.contentView
        guard let document = scrollView.documentView else { return false }
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
        guard delta != 0 else { return false }
        // Down the document is +y in a flipped clip view, -y in one that isn't.
        let height = document.frame.height
        let lowest = -insets.top
        let highest = max(lowest, height - clip.bounds.height + insets.bottom)
        var origin = clip.bounds.origin
        let current = flipped ? origin.y : height - clip.bounds.height - origin.y
        let next = min(max(current + delta, lowest), highest)
        guard next != current else { return false }
        origin.y = flipped ? next : height - clip.bounds.height - next
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
        return true
    }
}

/// The parts of the window drawn by SwiftUI whose issues can be swept: the board, My Issues' overview and the Inbox.
/// Each registers what it shows, as with right-click menus (`ContextMenus`), and one event monitor follows a ⌘-press that
/// lands on one of their issues. The list's table, on its own page as on an issue's, follows its presses itself.
@MainActor
final class SweepAreas {
    static let shared = SweepAreas()

    struct Area {
        var place: SweepPick.Place
        /// The issue a press at the point lands on, if a sweep can start there. Points are in window coordinates with the
        /// origin at the top left, as SwiftUI's `.global` space.
        var start: (CGPoint) -> String?
        /// The issues it can pick and where they are now, also those scrolled out of sight where it knows them.
        var rows: () -> [SweepRow]
        /// Cards side by side, as in columns, are swept by a rectangle; rows that reach across a list, by how far up or
        /// down the pointer is (false).
        var sideways = true
        /// Scrolls toward the pointer at an edge; nil when the sweep is over.
        var autoscroll: (CGPoint?) -> Void = { _ in }
    }

    private var areas: [UUID: Area] = [:]
    /// The press handed back to the view after it turned out to be a click, which the monitor lets through then.
    private var replaying: TimeInterval?

    func register(_ id: UUID, _ area: Area) {
        areas[id] = area
    }

    func remove(_ id: UUID) {
        areas[id] = nil
    }

    #if DEBUG
    /// The issues of every area and where they are, for the debug remote.
    var debugRows: [SweepRow] {
        areas.values.flatMap { $0.rows() }
    }
    #endif

    /// Follows a ⌘-press on an issue of an area until the button is up. Returns whether it took the press.
    func follow(_ event: NSEvent, model: AppModel) -> Bool {
        if let replaying, event.type == .leftMouseDown, event.timestamp == replaying {
            self.replaying = nil
            return false
        }
        guard SweepTracker.starts(event), let window = event.window, window === model.mainWindow, model.overlay == nil,
              let content = window.contentView else { return false }
        let height = content.bounds.height
        let topLeft = { (point: NSPoint) in CGPoint(x: point.x, y: height - point.y) }
        let point = topLeft(event.locationInWindow)
        // On the toolbar over the page, and on the peek, a notice or the selection bar over the board, the press is theirs.
        guard window.contentView?.superview?.hitTest(event.locationInWindow)?.isDescendant(of: content) == true,
              !ContextMenus.shared.isUnderFloatingView(point),
              let (area, id) = areas.values.lazy.compactMap({ area in area.start(point).map { (area, $0) } }).first
        else { return false }
        // Where on its issue the press started, which keeps the sweep's start there as the issues scroll. An issue can
        // show twice, as in Needs you and on its project's card: the row pressed is the one nearest to where it was.
        func pressed(in rows: [SweepRow], near point: CGPoint) -> CGRect? {
            rows.filter { $0.id == id }.map(\.frame).min { a, b in
                hypot(a.midX - point.x, a.midY - point.y) < hypot(b.midX - point.x, b.midY - point.y)
            }
        }
        let start = pressed(in: area.rows(), near: point)
        let offset = start.map { CGSize(width: point.x - $0.minX, height: point.y - $0.minY) }
        var anchor = point
        let tracker = SweepTracker(
            swept: { location in
                let rows = area.rows()
                if let offset, let frame = pressed(in: rows, near: anchor) {
                    anchor = CGPoint(x: frame.minX + offset.width, y: frame.minY + offset.height)
                }
                return SweepPick.swept(rows, from: anchor, to: topLeft(location), sideways: area.sideways)
            },
            autoscroll: { location in area.autoscroll(location.map(topLeft)) }
        )
        switch tracker.follow(event, on: id, in: area.place, window: window, model: model) {
        case .swept:
            break
        case .click(let up):
            // Handed back as it came, so that the view picks or opens as on any ⌘-click.
            replaying = event.timestamp
            window.postEvent(up, atStart: true)
            window.postEvent(event, atStart: true)
        }
        return true
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
    /// ⌘-drags over the issues of the board, My Issues' overview and the Inbox.
    func installSweepMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            let taken = MainActor.assumeIsolated { self.signedIn && SweepAreas.shared.follow(event, model: self) }
            return taken ? nil : event
        }
    }
}
#endif
