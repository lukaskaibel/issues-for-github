#if os(macOS)
#if DEBUG
import AppKit
import SwiftUI

/// How quickly menus answer the pointer, for the debug remote's `menutiming` and `menusweep`: a pointer moved by the
/// app itself, one step a frame as a quick hand moves, and how long the main thread was busy after each step. At 120 Hz
/// a frame lasts 8 ms; a step that takes longer is a frame the light or a submenu comes late. Run it on a window parked
/// off screen (`window 1440 900`), where dropdowns open off screen too and the real pointer can't reach them.
@MainActor
enum MenuTiming {
    private static var observer: CFRunLoopObserver?
    private static var busy: Double = 0
    private static var began: Double = 0
    private static var timer: Timer?
    /// The dropdown the pointer is in, so moving into another one first sends it an entered event.
    private static weak var inside: NSWindow?

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

    /// Steps run one a frame; each named one is timed until the next named one begins.
    @MainActor
    private final class Run {
        var steps: [() -> Void] = []
        var samples: [String: [Double]] = [:]
        var current: String?

        func step(_ name: String?, _ action: @escaping () -> Void) {
            steps.append { [self] in
                close()
                current = name
                action()
            }
        }

        func move(_ name: String, to point: NSPoint, level: Int) {
            step(name) { MenuTiming.hover(point, level: level) }
        }

        func wait(_ frames: Int) {
            for _ in 0..<frames { steps.append {} }
        }

        func finish(_ log: @escaping (String) -> Void, _ report: @escaping ([String: [Double]]) -> String) {
            steps.append { [self] in
                close()
                Dropdown.close()
                stopObserving()
                log(report(samples))
            }
            startObserving()
            busy = 0
            start(steps)
        }

        private func close() {
            if let current { samples[current, default: []].append(busy * 1000) }
            busy = 0
            current = nil
        }
    }

    private static func summary(_ samples: [Double]?) -> String {
        guard let samples, !samples.isEmpty else { return "none" }
        let sorted = samples.sorted()
        let mean = samples.reduce(0, +) / Double(samples.count)
        return String(format: "mean %.1f, median %.1f, p90 %.1f, max %.1f ms over %d, %d over 8 ms", mean, sorted[sorted.count / 2],
                      sorted[sorted.count * 9 / 10], sorted.last ?? 0, samples.count, samples.filter { $0 > 8 }.count)
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

    /// A pointer move to `point`, given from the window's top left, delivered as the window's tracking area would.
    private static func move(to point: NSPoint, in window: NSWindow) {
        let location = NSPoint(x: point.x, y: window.frame.height - point.y)
        guard let hosting = hostingView(in: window.contentView), let area = trackingArea(of: hosting) else { return }
        let time = ProcessInfo.processInfo.systemUptime
        if inside !== window {
            if let previous = inside, let old = hostingView(in: previous.contentView), let oldArea = trackingArea(of: old),
               let exit = enterExit(.mouseExited, at: location, in: previous, area: oldArea, time: time) {
                old.mouseExited(with: exit)
            }
            if let enter = enterExit(.mouseEntered, at: location, in: window, area: area, time: time) {
                hosting.mouseEntered(with: enter)
            }
            inside = window
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

    private static func hostingView(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if String(describing: type(of: view)).contains("HostingView") { return view }
        for sub in view.subviews { if let found = hostingView(in: sub) { return found } }
        return nil
    }

    // MARK: Busy time

    /// Adds up the time between the main thread waking and going back to sleep.
    private static func startObserving() {
        guard observer == nil else { return }
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { _, activity in
            let now = CACurrentMediaTime()
            if activity == .afterWaiting {
                began = now
            } else if began > 0 {
                busy += now - began
                began = 0
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func stopObserving() {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
    }
}
#endif
#endif
