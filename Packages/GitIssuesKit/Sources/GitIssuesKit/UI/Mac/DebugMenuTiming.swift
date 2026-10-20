#if os(macOS)
#if DEBUG
import AppKit
import SwiftUI

/// How quickly menus and the board answer the pointer, for the debug remote's `menutiming`, `menusweep` and
/// `boardsweep`: a pointer moved by the app itself, one step a frame as a quick hand moves, and how long the main thread
/// was busy after each step. At 120 Hz a frame lasts 8 ms; a step that takes longer is a frame the light or a submenu
/// comes late. Run it on a window parked off screen (`window 1440 900`), where dropdowns open off screen too and the
/// real pointer can't reach them.
///
/// A step lasts 1/60 s and holds two or three passes of the run loop, so besides the busy time of the whole step each
/// report gives the longest pass in it (one frame's work) and the main thread's own CPU time. Where the two part, the
/// thread was waiting rather than working: in a parked window SwiftUI's animations block on the render server.
@MainActor
enum MenuTiming {
    private static var observer: CFRunLoopObserver?
    /// When the pass under way began, on the clock and in the main thread's CPU time.
    private static var passBegan: (wall: Double, cpu: Double)?
    /// The passes since the step began.
    private static var current = Sample()
    private static var timer: Timer?
    /// The hosting view the pointer is in, so moving into another one first sends it an entered event.
    private static weak var inside: NSView?
    /// The last hosting view found under the pointer: walking the views on every move costs about half a millisecond.
    private static weak var underPointer: NSView?

    /// The main thread over one step, in milliseconds.
    struct Sample {
        /// Busy, from waking to going back to sleep, over all of the step's passes.
        var busy: Double = 0
        var cpu: Double = 0
        /// The longest single pass.
        var frame: Double = 0
        var cpuFrame: Double = 0
        var passes = 0
    }

    // MARK: Driving a menu

    /// Opens `menu` as a right-click would, off screen.
    static func show(_ menu: NSMenu, model: AppModel) {
        guard let content = model.mainWindow?.contentView else { return }
        Dropdown.close()
        let anchor = NSRect(x: 300, y: content.isFlipped ? 200 : content.bounds.height - 200, width: 1, height: 1)
        Dropdown.show(below: anchor, in: content, model: model) { close in GlassMenuView(menu: menu, close: close) }
        // Off every screen, also when the window isn't parked; its submenus open beside it.
        panels().first?.setFrameOrigin(NSPoint(x: -4000, y: 300))
        inside = nil
    }

    /// The open dropdowns, the menu first, with their sizes and which has the keyboard.
    static func describe(log: (String) -> Void) {
        let chain = panels()
        log("menutiming panels: \(chain.count) open" + chain.enumerated().map { index, panel in
            " [\(index)] \(Int(panel.frame.width))x\(Int(panel.frame.height))\(NSApp.keyWindow === panel ? " key" : "")"
        }.joined())
    }

    /// Moves the pointer to `point`, from the top left of the open dropdown `level` (0 the menu, 1 its submenu).
    static func hover(_ point: NSPoint, level: Int) {
        let chain = panels()
        if chain.indices.contains(level) { move(to: point, in: chain[level]) }
    }

    /// Moves the pointer to `point`, from the top left of the main window, and leaves it there: for a snapshot with
    /// something under the pointer.
    static func point(_ point: NSPoint, model: AppModel) {
        if let window = model.mainWindow { move(to: point, in: window) }
    }

    /// A click at `point`, from the top left of the open dropdown `level`, through the event queue as a real one comes.
    static func click(_ point: NSPoint, level: Int) {
        let chain = panels()
        guard chain.indices.contains(level) else { return }
        let panel = chain[level]
        let location = NSPoint(x: point.x, y: panel.frame.height - point.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    // MARK: Timing

    /// Down the whole menu, then resting on the row titled `rest` until its submenu opens, then down the submenu.
    static func sweep(_ menu: NSMenu, rest: String, model: AppModel, log: @escaping (String) -> Void) {
        show(menu, model: model)
        let run = Run()
        run.wait(20)
        let height = panels().first?.frame.height ?? 0
        for y in stride(from: CGFloat(44), to: height - 8, by: 5) {
            run.move("sweep", to: NSPoint(x: 80, y: y), level: 0)
        }
        if let index = visible(menu).firstIndex(where: { $0.title == rest }) {
            run.move("rest", to: NSPoint(x: 80, y: rowY(index, in: menu)), level: 0)
            run.wait(30)
            for y in stride(from: CGFloat(44), to: 44 + 30 * 7, by: 5) {
                run.move("submenu", to: NSPoint(x: 60, y: y), level: 1)
            }
        }
        run.finish(log) { samples in
            "menutiming sweep: " + summary(samples["sweep"]) + "; rest on \(rest) " + summary(samples["rest"]) + "; in its submenu " + summary(samples["submenu"])
        }
    }

    /// Up and down the rows without submenus at the end of the menu: the light moving and nothing else.
    static func plain(_ menu: NSMenu, model: AppModel, log: @escaping (String) -> Void) {
        show(menu, model: model)
        let run = Run()
        run.wait(20)
        let height = panels().first?.frame.height ?? 0
        let down = Array(stride(from: height - 170, to: height - 8, by: 5))
        for _ in 0..<12 {
            for y in down + down.reversed() { run.move("plain", to: NSPoint(x: 80, y: y), level: 0) }
        }
        run.finish(log) { "menutiming plain: " + summary($0["plain"]) }
    }

    /// Rests on the row titled `row` until its submenu opens, then on the row under it, `times` times.
    static func submenu(_ menu: NSMenu, row: String, times: Int, model: AppModel, log: @escaping (String) -> Void) {
        guard let index = visible(menu).firstIndex(where: { $0.title == row }) else { return log("menutiming: no row \(row)") }
        show(menu, model: model)
        let run = Run()
        run.wait(20)
        for _ in 0..<times {
            run.move("open", to: NSPoint(x: 80, y: rowY(index, in: menu)), level: 0)
            run.wait(20)
            run.move("leave", to: NSPoint(x: 80, y: rowY(index + 1, in: menu)), level: 0)
            run.wait(20)
        }
        run.finish(log) { "menutiming submenu \(row): " + summary($0["open"]) }
    }

    /// Opens and closes the menu `times` times, its first drawing included.
    static func opening(_ build: @escaping () -> NSMenu, times: Int, model: AppModel, log: @escaping (String) -> Void) {
        let run = Run()
        for _ in 0..<times {
            run.step("open") { show(build(), model: model) }
            run.wait(20)
            run.step(nil) { Dropdown.close() }
            run.wait(15)
        }
        run.finish(log) { "menutiming open: " + summary($0["open"]) }
    }

    /// Up and down between `from` and `to` at `x`, three times, over the open dropdown or, with `main`, over the app's
    /// window (the command palette).
    static func sweep(main: Bool, x: CGFloat, from: CGFloat, to: CGFloat, model: AppModel, log: @escaping (String) -> Void) {
        guard let target: NSWindow = main ? model.mainWindow : panels().last else { return log("menusweep: nothing open") }
        inside = nil
        let run = Run()
        let down = Array(stride(from: from, through: to, by: 5))
        for _ in 0..<3 {
            for y in down + down.reversed() {
                run.step("move") { move(to: NSPoint(x: x, y: y), in: target) }
            }
        }
        run.finish(log) { "menusweep: " + summary($0["move"]) }
    }

    // MARK: The board

    /// Up and down a board column between `from` and `to` at `x`, from the window's top left, three times. Steps that
    /// bring something new under the pointer (a card, one of its parts, a fold arrow, a number, an epic's header) are
    /// counted apart from steps that only move within it, which should cost next to nothing.
    static func sweepBoard(x: CGFloat, from: CGFloat, to: CGFloat, model: AppModel, log: @escaping (String) -> Void) {
        guard let window = model.mainWindow, model.scopeProjectId != nil else { return log("boardsweep: no board") }
        inside = nil
        let drag = model.boardDrag
        let run = Run()
        var previous = ""
        var cards: [String] = []
        let down = Array(stride(from: from, through: to, by: 5))
        for _ in 0..<3 {
            for y in down + down.reversed() {
                run.step({
                    let point = CGPoint(x: x - drag.boardFrameInWindow.minX, y: y - drag.boardFrameInWindow.minY)
                    let items = model.columns.flatMap(\.items)
                    let card = drag.card(at: point, in: items)
                    let header = drag.header(at: point)
                    let under = [
                        card?.id, drag.part(at: point, in: items).map { "\($0.kind)" }, drag.fold(at: point, in: items)?.id,
                        drag.number(at: point, in: items)?.id, header?.epic, header.map { drag.isOnFold(point, of: $0) ? "fold" : nil } ?? nil,
                    ].map { $0 ?? "-" }.joined(separator: "|")
                    defer { previous = under }
                    if let id = card?.id, cards.last != id { cards.append(id) }
                    return under == previous ? "same" : "change"
                }) {
                    move(to: NSPoint(x: x, y: y), in: window)
                }
            }
        }
        CardPaintTiming.reset()
        run.finish(log) { samples in
            "boardsweep: " + summary((samples["change"] ?? []) + (samples["same"] ?? []))
                + "; \(cards.count) times onto one of \(Set(cards).count) cards; " + paintedCards()
        }
    }

    /// "37 cards painted, 0.62 ms each", since the timing was last reset.
    static func paintedCards() -> String {
        String(format: "%d cards painted, %.2f ms each", CardPaintTiming.count, CardPaintTiming.milliseconds / Double(max(CardPaintTiming.count, 1)))
    }

    // MARK: Steps

    /// Steps run one a frame; each named one is timed until the next one begins.
    @MainActor
    private final class Run {
        var steps: [() -> Void] = []
        var samples: [String: [Sample]] = [:]
        /// The names in the order they first came, for the report.
        var names: [String] = []
        var current: String?

        func step(_ name: String?, _ action: @escaping () -> Void) {
            step({ name }, action)
        }

        /// A step named when it runs, from what is on screen by then.
        func step(_ name: @escaping () -> String?, _ action: @escaping () -> Void) {
            steps.append { [self] in
                close()
                current = name()
                action()
            }
        }

        func move(_ name: String, to point: NSPoint, level: Int) {
            step(name) { MenuTiming.hover(point, level: level) }
        }

        func wait(_ frames: Int) {
            for _ in 0..<frames { steps.append {} }
        }

        /// Logs `report`'s line, then for each kind of step its frames and CPU time.
        func finish(_ log: @escaping (String) -> Void, _ report: @escaping ([String: [Sample]]) -> String) {
            steps.append { [self] in
                close()
                Dropdown.close()
                stopObserving()
                log(report(samples))
                for name in names { details(name, samples[name] ?? []).forEach(log) }
            }
            startObserving()
            MenuTiming.current = Sample()
            start(steps)
        }

        private func close() {
            if let current {
                if samples[current] == nil { names.append(current) }
                samples[current, default: []].append(MenuTiming.current)
            }
            MenuTiming.current = Sample()
            current = nil
        }
    }

    private static func summary(_ samples: [Sample]?) -> String {
        summary(samples?.map(\.busy))
    }

    private static func summary(_ values: [Double]?) -> String {
        guard let values, !values.isEmpty else { return "none" }
        let sorted = values.sorted()
        let mean = values.reduce(0, +) / Double(values.count)
        return String(format: "mean %.1f, median %.1f, p90 %.1f, max %.1f ms over %d, %d over 8 ms", mean, sorted[sorted.count / 2],
                      sorted[sorted.count * 9 / 10], sorted.last ?? 0, values.count, values.filter { $0 > 8 }.count)
    }

    private static func details(_ name: String, _ samples: [Sample]) -> [String] {
        let passes = Double(samples.map(\.passes).reduce(0, +)) / Double(max(samples.count, 1))
        return [
            "  \(name) steps:      " + summary(samples.map(\.busy)) + String(format: ", %.1f passes each", passes),
            "  \(name) frames:     " + summary(samples.map(\.frame)),
            "  \(name) cpu:        " + summary(samples.map(\.cpu)),
            "  \(name) cpu frames: " + summary(samples.map(\.cpuFrame)),
        ]
    }

    private static func start(_ steps: [() -> Void]) {
        var step = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard step < steps.count else { return timer.invalidate() }
                steps[step]()
                step += 1
            }
        }
    }

    // MARK: Pointer

    private static func visible(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.filter { !$0.isHidden }
    }

    /// Where the middle of a row is, from the top of the menu: under the search field, rows as tall as a picker's,
    /// lines between groups.
    private static func rowY(_ index: Int, in menu: NSMenu) -> CGFloat {
        var y: CGFloat = 42
        for item in visible(menu).prefix(index) {
            y += item.isSeparatorItem ? 11 : PickerRow.height
        }
        return y + PickerRow.height / 2
    }

    /// The open dropdowns, the menu first and then each submenu opened from it.
    private static func panels() -> [DropdownPanel] {
        var chain: [DropdownPanel] = []
        var next = NSApp.windows.first { ($0 as? DropdownPanel).map { $0.isVisible && !($0.opener is DropdownPanel) } ?? false } as? DropdownPanel
        while let panel = next {
            chain.append(panel)
            next = Dropdown.panel(openedFrom: panel)
        }
        return chain
    }

    /// A pointer move to `point`, given from the window's top left, delivered as the tracking area of the hosting view
    /// under it would.
    private static func move(to point: NSPoint, in window: NSWindow) {
        let location = NSPoint(x: point.x, y: window.frame.height - point.y)
        guard let hosting = hostingView(at: location, in: window), let area = trackingArea(of: hosting) else { return }
        let time = ProcessInfo.processInfo.systemUptime
        if inside !== hosting {
            if let previous = inside, let previousWindow = previous.window, let oldArea = trackingArea(of: previous),
               let exit = enterExit(.mouseExited, at: location, in: previousWindow, area: oldArea, time: time) {
                previous.mouseExited(with: exit)
            }
            if let enter = enterExit(.mouseEntered, at: location, in: window, area: area, time: time) {
                hosting.mouseEntered(with: enter)
            }
            inside = hosting
        }
        if let event = NSEvent.mouseEvent(with: .mouseMoved, location: location, modifierFlags: [], timestamp: time,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
            hosting.mouseMoved(with: event)
        }
    }

    private static func enterExit(_ type: NSEvent.EventType, at location: NSPoint, in window: NSWindow, area: NSTrackingArea, time: TimeInterval) -> NSEvent? {
        let pointer = Unmanaged.passUnretained(area).toOpaque()
        return NSEvent.enterExitEvent(with: type, location: location, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber,
                                      context: nil, eventNumber: 0, trackingNumber: Int(bitPattern: pointer), userData: pointer)
    }

    private static func trackingArea(of view: NSView) -> NSTrackingArea? {
        view.trackingAreas.first { $0.owner === view }
    }

    /// The innermost hosting view that tracks the pointer at `location`, in window coordinates: in the main window the
    /// board's or the sidebar's rather than the first one in the tree, which is the toolbar's. A dropdown without one
    /// under the point gets its first.
    private static func hostingView(at location: NSPoint, in window: NSWindow) -> NSView? {
        if let found = underPointer, found.window === window, found.convert(found.bounds, to: nil).contains(location) { return found }
        var found: NSView?
        func walk(_ view: NSView) {
            guard !view.isHidden, view.convert(view.bounds, to: nil).contains(location) else { return }
            if isHosting(view), trackingArea(of: view) != nil { found = view }
            view.subviews.forEach(walk)
        }
        if let content = window.contentView { walk(content) }
        underPointer = found
        return found ?? firstHostingView(in: window.contentView)
    }

    private static func firstHostingView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if isHosting(view) { return view }
        for sub in view.subviews { if let found = firstHostingView(in: sub) { return found } }
        return nil
    }

    private static func isHosting(_ view: NSView) -> Bool {
        String(describing: type(of: view)).contains("HostingView")
    }

    // MARK: Busy time

    nonisolated private static func threadCPU() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e6
    }

    /// Adds up the time between the main thread waking and going back to sleep, on the clock and in its CPU time.
    private static func startObserving() {
        guard observer == nil else { return }
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { _, activity in
            MainActor.assumeIsolated {
                let now = CACurrentMediaTime() * 1000
                if activity == .afterWaiting {
                    passBegan = (now, threadCPU())
                } else if let began = passBegan {
                    let wall = now - began.wall
                    let cpu = threadCPU() - began.cpu
                    current.busy += wall
                    current.cpu += cpu
                    current.frame = max(current.frame, wall)
                    current.cpuFrame = max(current.cpuFrame, cpu)
                    current.passes += 1
                    passBegan = nil
                }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func stopObserving() {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
        passBegan = nil
    }
}
#endif
#endif
