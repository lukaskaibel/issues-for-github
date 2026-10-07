#if os(macOS)
#if DEBUG
import AppKit
import SwiftUI

/// Development-only remote control. Launch with `-debugCommandFile <path>` and append lines to that file
/// to drive the app (open an issue, run a drag, go offline) so states can be checked without a mouse.
@MainActor
enum DebugRemote {
    private static var processed = 0
    private static var timer: Timer?
    private static var dragTimer: Timer?
    private static var scrollTimer: Timer?
    private static var activity: NSObjectProtocol?

    static func startIfRequested(model: AppModel) {
        guard let path = UserDefaults.standard.string(forKey: "debugCommandFile") else { return }
        // Keep timers running at full rate while the window is in the background.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Debug remote")
        processed = (try? String(contentsOfFile: path, encoding: .utf8))?.split(separator: "\n").count ?? 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
                let lines = text.split(separator: "\n").map(String.init)
                while processed < lines.count {
                    run(lines[processed], model: model)
                    processed += 1
                }
            }
        }
    }

    static func log(_ text: String) {
        guard let path = UserDefaults.standard.string(forKey: "debugCommandFile") else { return }
        let url = URL(fileURLWithPath: path + ".log")
        let line = Data((text + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    private static func item(_ token: String, _ model: AppModel) -> Item? {
        guard let number = Int(token) else { return nil }
        return model.scopedItems.first { $0.number == number } ?? model.allItems.first { $0.number == number }
    }

    /// The only project test commands may change.
    static let sandboxTitle = "Git Issues Sandbox"

    private static func run(_ line: String, model: AppModel) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        let readOnly: Set<String> = ["select", "dump", "snapshot", "notice", "mode", "open", "close", "focus", "scrolltest", "appearance", "icon", "settings", "back", "forward", "wait", "rendersync", "phase", "responder", "click", "key", "keycode", "keycmd", "overlay", "focusdesc", "scrolllist", "rightclick", "listdump", "togglesection", "nav", "leave", "trace", "renderhover", "hideproject", "showproject", "rendersidebar", "pick", "picks", "peek", "window", "demo", "dragimage", "entry", "inboxdump", "menudump"]
        // Sample data never reaches GitHub, so everything may be tried there.
        if let command = parts.first, !readOnly.contains(command), !model.isDemo, model.currentProject?.title != sandboxTitle {
            log("refused \"\(line)\": the open project is not the sandbox")
            return
        }
        switch parts.first {
        case "select":
            if argument == "mine" {
                model.select(.myIssues)
            } else if argument == "inbox" {
                model.select(.inbox)
            } else if argument.hasPrefix("repo "), let repo = model.boardRepositories.first(where: {
                $0.nameWithOwner.localizedCaseInsensitiveContains(argument.dropFirst(5))
            }) {
                model.select(.repository(repo.id))
            } else if let project = model.projects.first(where: { $0.title.localizedCaseInsensitiveContains(argument) }) {
                model.select(.project(project.id))
            }
        case "entry":
            // entry <number>: selects the Inbox entry about that issue, as a click does; "entry none" clears it.
            let entry = model.visibleInbox.first { "\($0.number ?? -1)" == argument || $0.displayNumber(withRepo: true) == argument }
            model.selectInboxEntry(entry)
        case "inboxdump":
            for entry in model.inboxEntries {
                let summary = model.inboxSummary(entry)
                log("inbox \(entry.displayNumber(withRepo: true)) \(entry.bucket.rawValue) unread=\(model.isUnread(entry)) archived=\(entry.isArchived) \(summary.sign.rawValue): \(summary.lead) \(summary.excerpt ?? "")")
            }
            log("inbox unread=\(model.inboxUnreadCount) selected=\(model.inboxSelected?.displayNumber(withRepo: true) ?? "-") picked=\(model.inboxPicked.count) undo=\(model.inboxUndo?.message ?? "-") pending=\(model.pendingCount)")
        case "mode":
            model.closeDetail()
            withAnimation(Theme.spring) { model.viewMode = argument == "list" ? .list : .board }
        case "open":
            if let item = item(argument, model) { model.open(item) }
        case "close":
            model.closeDetail()
        case "focus":
            model.focusedItemId = item(argument, model)?.id
        case "overlay":
            // overlay palette|new|none, or overlay parent|subissue|blockedby|blocking <number> for a relation picker.
            let bits = argument.split(separator: " ").map(String.init)
            let target = bits.count > 1 ? item(bits[1], model)?.id : nil
            switch (bits.first, target) {
            case ("palette", _): model.overlay = .palette(.root)
            case ("new", _): model.overlay = .newIssue(statusId: nil, parentItemId: nil)
            case ("parent", let id?): model.overlay = .palette(.parent(itemId: id))
            case ("subissue", let id?): model.overlay = .palette(.addSubIssue(itemId: id))
            case ("blockedby", let id?): model.overlay = .palette(.blockedBy(itemId: id))
            case ("blocking", let id?): model.overlay = .palette(.blocking(itemId: id))
            default: model.overlay = nil
            }
        case "menudump":
            // menudump <number>: the issue's right-click menu, one entry per line, submenus indented.
            if let item = item(argument, model) {
                func dump(_ menu: NSMenu, _ depth: Int) {
                    for entry in menu.items {
                        log(String(repeating: "  ", count: depth) + (entry.isSeparatorItem ? "—" : entry.title))
                        if let submenu = entry.submenu { dump(submenu, depth + 1) }
                    }
                }
                dump(ItemMenuBuilder(model: model, item: item).menu(), 0)
            }
        case "key":
            sendKeys(argument)
        case "requestdelete":
            if let item = item(argument, model) { model.requestDelete(item) }
        case "confirmdelete":
            // What the confirmation's Delete button does.
            if let item = model.deletionCandidate { model.delete(item) }
        case "focusdesc":
            // Puts the caret at the end of the open issue's description.
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 }),
               let editor = findDescription(in: window.contentView) {
                window.makeFirstResponder(editor)
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            }
        case "keycmd":
            // keycmd <character>: a menu shortcut such as ⌘N.
            if let character = argument.first {
                sendKey(characters: String(character), code: 0, modifiers: .command)
            }
        case "click", "rightclick":
            // click|rightclick <x> <y> in points from the window's top-left corner.
            let bits = argument.split(separator: " ").compactMap { Double($0) }
            if bits.count == 2 { click(at: CGPoint(x: bits[0], y: bits[1]), right: parts.first == "rightclick") }
        case "responder":
            // Which control has the keyboard focus: the field editor means a single-line text field.
            let window = NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.frame.width > 600 }
            let responder = window?.firstResponder
            var description = responder.map { String(describing: type(of: $0)) } ?? "nil"
            if let text = responder as? NSTextView {
                description += text.isFieldEditor ? " (single-line field, text: \"\(text.string)\")" : " (multi-line editor)"
                if let field = text.delegate as? NSView, let content = window?.contentView {
                    let frame = field.convert(field.bounds, to: content)
                    description += " at x=\(Int(frame.minX)) y=\(Int(content.bounds.height - frame.maxY)) w=\(Int(frame.width))"
                }
                if let key = NSApp.keyWindow { description += " keyWindow=\(key.frame.width)" } else { description += " keyWindow=nil" }
            }
            log("responder: \(description) overlay=\(String(describing: model.overlay))")
        case "keycode":
            // keycode <code> [cmd] [shift]
            let bits = argument.split(separator: " ").map(String.init)
            if let code = bits.first.flatMap({ UInt16($0) }) {
                var modifiers: NSEvent.ModifierFlags = []
                if bits.contains("cmd") { modifiers.insert(.command) }
                if bits.contains("shift") { modifiers.insert(.shift) }
                if bits.contains("opt") { modifiers.insert(.option) }
                let characters = [36: "\r", 51: "\u{7F}", 53: "\u{1B}", 49: " ", 7: "x", 38: "j", 40: "k", 0: "a"][code] ?? ""
                sendKey(characters: modifiers.contains(.shift) ? characters.uppercased() : characters, code: code, modifiers: modifiers)
            }
        case "status":
            let bits = argument.split(separator: " ", maxSplits: 1).map(String.init)
            if bits.count == 2, let item = item(bits[0], model),
               let option = model.statusOptions(projectId: item.projectId).first(where: { $0.name.caseInsensitiveCompare(bits[1]) == .orderedSame }) {
                withAnimation(Theme.spring) { model.setStatus(item, to: option) }
            }
        case "offline":
            GraphQLClient.simulateOffline.withLock { $0 = argument == "on" }
            model.refresh()
        case "drag":
            // drag <number> <row index> <hold|drop> <column name>
            let bits = argument.split(separator: " ", maxSplits: 3).map(String.init)
            if bits.count == 4, let item = item(bits[0], model), let index = Int(bits[1]) {
                drag(item, toColumn: bits[3], index: index, hold: bits[2] == "hold", model: model)
            }
        case "dragcolumn":
            // dragcolumn <hold|drop> <columns to move, e.g. -2> <column name>
            let bits = argument.split(separator: " ", maxSplits: 2).map(String.init)
            if bits.count == 3, let steps = Double(bits[1]),
               let column = model.columns.first(where: { $0.title.caseInsensitiveCompare(bits[2]) == .orderedSame }),
               let frame = model.boardDrag.columnFrames[column.id] {
                let step = frame.width + 12
                var tick = 0
                dragTimer?.invalidate()
                dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
                    MainActor.assumeIsolated {
                        tick += 1
                        let t = min(Double(tick) / 30, 1)
                        model.boardDrag.dragColumn(column, translation: CGFloat(steps * t) * step * 0.92, step: step, model: model)
                        if tick >= 30 {
                            timer.invalidate()
                            if bits[0] == "drop" { model.boardDrag.dropColumn(model: model) }
                        }
                    }
                }
            }
        case "dropcolumn":
            model.boardDrag.dropColumn(model: model)
        case "movesection":
            // movesection <section title> before <section title|end>
            let bits = argument.components(separatedBy: " before ")
            if bits.count == 2, let moving = model.sections.first(where: { $0.title == bits[0] }) {
                model.moveListSection(moving.id, before: model.sections.first { $0.title == bits[1] }?.id)
            }
        case "drop":
            model.boardDrag.ended(model: model)
        case "canceldrag":
            model.dragCancelToken += 1
        case "appearance":
            if let setting = AppearanceSetting(rawValue: argument) { model.appearance = setting }
        case "icon":
            if let choice = AppIconChoice(rawValue: argument) { model.appIcon = choice }
        case "settings":
            model.settingsRequest += 1
        case "back":
            model.goBack()
        case "forward":
            model.goForward()
        case "togglesection":
            if let section = model.sections.first(where: { $0.title == argument }) { model.toggleSection(section.id) }
        case "listdump":
            if let root = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 })?.contentView {
                func find(_ view: NSView) -> HoverTableView? {
                    if let table = view as? HoverTableView { return table }
                    for subview in view.subviews { if let found = find(subview) { return found } }
                    return nil
                }
                let summary: String = find(root)?.coordinator?.listSummary ?? "no table"
                log("list: " + summary)
            }
        case "listdrop", "dragimage":
            // listdrop <number> <row>: drops the issue in the list above that row, as a drag would.
            // dragimage <number> <path>: the card an issue's row lifts off as, as a PNG.
            let bits = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard bits.count == 2, let item = item(bits[0], model),
                  let root = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 })?.contentView else { break }
            func find(_ view: NSView) -> HoverTableView? {
                if let table = view as? HoverTableView { return table }
                for subview in view.subviews { if let found = find(subview) { return found } }
                return nil
            }
            guard let table = find(root), let coordinator = table.coordinator else { break }
            if parts.first == "listdrop", let row = Int(bits[1]) {
                log("listdrop: \(coordinator.dropItem(item.id, above: row))")
            } else if let row = (0..<table.numberOfRows).first(where: { coordinator.item(at: $0)?.id == item.id }),
                      let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? IssueRowCell,
                      let image = cell.dragImage(), let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: bits[1]))
            }
        case "scrolllist":
            // scrolllist <y>: scrolls the tallest scroll view to y points from the top.
            if let root = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 })?.contentView, let y = Double(argument) {
                var views: [NSScrollView] = []
                func collect(_ view: NSView) {
                    if let scroll = view as? NSScrollView { views.append(scroll) }
                    view.subviews.forEach(collect)
                }
                collect(root)
                if let scroll = views.max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }) {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: y - scroll.contentInsets.top))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
        case "scrolltest":
            scrollTest(label: argument)
        case "snapshot":
            // snapshot <path>: the window as a PNG, drawn by the app itself, so it works while the screen is locked
            // (materials and vibrancy come out flat).
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 }),
               let view = window.contentView?.superview ?? window.contentView, let layer = view.layer {
                let scale = window.backingScaleFactor
                let size = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
                if let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    context.setFillColor(window.backgroundColor.cgColor)
                    context.fill(CGRect(origin: .zero, size: size))
                    context.scaleBy(x: scale, y: scale)
                    layer.render(in: context)
                    // Open dropdowns are windows of their own, each opened from the one before; draw them where they
                    // are on screen.
                    func drawChildren(of parent: NSWindow) {
                        for child in parent.childWindows ?? [] where child.isVisible {
                            guard let childLayer = (child.contentView?.superview ?? child.contentView)?.layer else { continue }
                            context.saveGState()
                            context.translateBy(x: child.frame.minX - window.frame.minX, y: child.frame.minY - window.frame.minY)
                            childLayer.render(in: context)
                            context.restoreGState()
                            drawChildren(of: child)
                        }
                    }
                    drawChildren(of: window)
                    if let image = context.makeImage() {
                        let rep = NSBitmapImageRep(cgImage: image)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: argument))
                    }
                }
            }
        case "window":
            // window <width> <height>: sizes the window in points for screenshots and moves it off the screen, where
            // the pointer can't put hover states into the picture and the window is out of the way.
            let size = argument.split(separator: " ").compactMap { Double($0) }
            if size.count == 2, let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 }) {
                let screens = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
                window.ignoresMouseEvents = true
                window.setFrame(CGRect(x: screens.minX - size[0] - 400, y: screens.minY, width: size[0], height: size[1]), display: true)
                log("window: \(window.frame)")
            }
        case "demo":
            // demo off: leaves the sample data for the sign-in screen; demo on: enters it again.
            if argument == "off" { model.leaveDemo() } else { model.enterDemo() }
        case "trace":
            Dropdown.trace = { log("dropdown: " + $0) }
        case "nav":
            // Where the app is and the history behind it, oldest first; * marks the current place.
            let places = model.history.enumerated().map { index, place in
                let name = place.itemId.flatMap { id in model.allItems.first { $0.id == id }?.displayNumber } ?? place.viewMode.rawValue
                return (index == model.historyIndex ? "*" : "") + name
            }
            log("nav: open=\(model.openItem?.displayNumber ?? "-") history=\(places.joined(separator: " > "))")
        case "leave":
            model.leaveIssue()
        case "dump":
            let drag = model.boardDrag
            log("active=\(drag.active.map { "\($0.item.displayNumber) loc=\($0.location) lifted=\($0.lifted) settling=\($0.settling)" } ?? "nil") target=\(String(describing: drag.target))")
            for column in model.columns {
                log("  column \(column.title) frame=\(drag.columnFrames[column.id].map { "\($0)" } ?? "nil") cards=\(column.items.compactMap { item in drag.cardFrames[item.id].map { "\(item.displayNumber):\(Int($0.minX)),\(Int($0.minY))" } }.joined(separator: " "))")
            }
            log("  project=\(model.currentProject?.title ?? "-") mode=\(model.viewMode.rawValue)")
            log("  columns=\(model.columns.map(\.title).joined(separator: " | ")) sections=\(model.sections.map(\.title).joined(separator: " | ")) columnDrag=\(String(describing: drag.column))")
            log("  deletion=\(model.deletionCandidate?.displayNumber ?? "-") canDelete18=\(model.scopedItems.first { $0.number == 18 }.map { model.canDelete($0) } ?? false)")
            log("  overlay=\(String(describing: model.overlay)) open=\(model.openItem?.displayNumber ?? "-") focus=\(model.targetItem?.displayNumber ?? "-") phase=\(model.status.phase) pending=\(model.pendingCount)")
        case "column":
            // column add <name> | column delete <name> | column rename <old>=<new>
            guard let projectId = model.currentProjectId else { break }
            var options = model.statusOptions(projectId: projectId).map(\.remote)
            let bits = argument.split(separator: " ", maxSplits: 1).map(String.init)
            guard bits.count == 2 else { break }
            switch bits[0] {
            case "add": options.append(RemoteOption(id: nil, name: bits[1], color: "PINK"))
            case "delete": options.removeAll { $0.name == bits[1] }
            case "rename":
                let names = bits[1].split(separator: "=").map(String.init)
                if names.count == 2, let index = options.firstIndex(where: { $0.name == names[0] }) { options[index].name = names[1] }
            default: break
            }
            withAnimation(Theme.spring) { model.saveColumns(projectId: projectId, options) }
        case "body":
            if let item = model.openItem { model.setBody(item, to: argument.replacingOccurrences(of: "\\n", with: "\n")) }
        case "forget":
            if let projectId = model.currentProjectId {
                try? model.db.writer.write { db in
                    try db.execute(sql: "DELETE FROM item WHERE projectId = ?", arguments: [projectId])
                    try db.execute(sql: "DELETE FROM fieldOption WHERE projectId = ?", arguments: [projectId])
                    try db.execute(
                        sql: "UPDATE project SET lastSyncedAt = NULL, remoteUpdatedAt = NULL, itemsTotal = NULL WHERE id = ?",
                        arguments: [projectId]
                    )
                }
                model.refresh()
            }
        case "rendersync":
            // The account in the sidebar with each sync dot, the cards for each state that needs attention, and the
            // account menu, written next to the command file.
            guard let base = UserDefaults.standard.string(forKey: "debugCommandFile") else { break }
            let dark = NSApp.effectiveAppearance.isDark
            let styles: [SyncDotStyle] = [.synced, .queued, .sending, .offline, .attention]
            let attentions: [SyncAttention] = [
                .offline(pending: 3), .offline(pending: 0), .conflict(count: 1, number: "#15", itemId: "-"),
                .conflict(count: 2, number: "#15", itemId: "-"), .failed("The network connection was lost."),
            ]
            let sidebar = VStack(alignment: .leading, spacing: 10) {
                ForEach(styles, id: \.self) { style in
                    HStack(spacing: 8) {
                        StatusAvatar(size: 20, style: style)
                        Text(model.viewer?.login ?? "GitHub").font(.uiSemibold)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                }
                ForEach(attentions, id: \.self) { SyncHintCard(attention: $0) }
            }
            let renderers = [
                ("sync-sidebar", ImageRenderer(content: AnyView(sidebar
                    .padding(10)
                    .frame(width: Theme.sidebarWidth)
                    .background(Theme.window)
                    .environment(model)
                    .environment(\.colorScheme, dark ? .dark : .light)))),
                ("sync-menu", ImageRenderer(content: AnyView(HStack(alignment: .top, spacing: 12) {
                    AccountDropdown(close: {})
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.popover))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
                    AppearanceDropdown(close: {})
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.popover))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
                }
                    .padding(16)
                    .background(Theme.window)
                    .environment(model)
                    .environment(\.colorScheme, dark ? .dark : .light)))),
            ]
            for (name, renderer) in renderers {
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(base).\(name).png"))
                }
            }
            log("rendered sync states")
        case "phase":
            // phase idle|syncing|offline|failed: shows a sync state on screen until the next round of syncing.
            switch argument {
            case "syncing": model.status.phase = .syncing
            case "offline": model.status.phase = .offline
            case "failed": model.status.phase = .failed("The network connection was lost.")
            default: model.status.phase = .idle
            }
        case "pick":
            // pick <number> [<number>…]: adds issues to the selection, or takes them out.
            for number in argument.split(separator: " ").compactMap({ Int($0) }) {
                if let item = model.scopedItems.first(where: { $0.number == number }) { model.toggleSelection(item) }
            }
        case "picks":
            log("picks: selected=\(model.selectedItems.map { "\($0.displayNumber):\(model.priorityOption(of: $0)?.name ?? "none")" }.joined(separator: " ")) peek=\(model.peekItem?.displayNumber ?? "-") focus=\(model.focusedItemId.flatMap { id in model.scopedItems.first { $0.id == id }?.displayNumber } ?? "-")")
        case "peek":
            // peek <number>: moves the focus there and peeks at it; without a number, toggles the peek.
            if let item = item(argument, model) {
                model.moveFocus(to: item.id)
                if model.peekItemId == nil { model.togglePeek() }
            } else {
                model.togglePeek()
            }
        case "hideproject", "showproject":
            // Only changes what the sidebar shows on this Mac.
            if let project = model.projects.first(where: { $0.title.localizedCaseInsensitiveContains(argument) }) {
                model.setHidden(project, parts.first == "hideproject")
            }
        case "rendersidebar":
            // rendersidebar <name>: the sidebar as it is now, written next to the command file.
            guard let base = UserDefaults.standard.string(forKey: "debugCommandFile") else { break }
            // Scroll views draw empty in an image renderer, so the project list is drawn on its own below.
            let open = model.projects.filter { !$0.closed }
            let renderer = ImageRenderer(
                content: VStack(alignment: .leading, spacing: 2) {
                    let hidden = open.filter { model.hiddenProjectIds.contains($0.id) }
                    ForEach(open.filter { !model.hiddenProjectIds.contains($0.id) }) { ProjectRow(project: $0, hidden: false) }
                    HiddenGroup(count: hidden.count, noun: "projects") { EmptyView() }
                    HiddenGroup(count: hidden.count, noun: "projects", rows: {
                        ForEach(hidden) { ProjectRow(project: $0, hidden: true) }
                    }, expanded: true)
                    ForEach(model.boardRepositories.filter { !model.hiddenRepositoryIds.contains($0.id) }) { RepositoryRow(repo: $0, hidden: false) }
                }
                    .padding(10)
                    .environment(model)
                    .frame(width: Theme.sidebarWidth)
                    .background(Theme.window)
                    .environment(\.colorScheme, NSApp.effectiveAppearance.isDark ? .dark : .light)
            )
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(base).sidebar-\(argument).png"))
            }
        case "renderhover":
            // renderhover <number> [<number>…]: each issue as a card and a list row, once per hovered part,
            // written next to the command file, to check the hover shapes.
            guard let base = UserDefaults.standard.string(forKey: "debugCommandFile") else { break }
            let kinds: [PickerKind?] = [nil, .priority, .status, .labels, .subIssues, .assignees]
            let dark = NSApp.effectiveAppearance.isDark
            for number in argument.split(separator: " ").compactMap({ Int($0) }) {
                guard let item = model.scopedItems.first(where: { $0.number == number }) else { continue }
                for kind in kinds {
                    let name = kind.map { "\($0)" } ?? "none"
                    let renderer = ImageRenderer(
                        content: CardView(card: model.cardModel(for: item), width: 300, hoveredPart: kind)
                            .padding(10)
                            .background(Theme.panel)
                            .environment(\.colorScheme, dark ? .dark : .light)
                    )
                    renderer.scale = 2
                    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: "\(base).card-\(number)-\(name).png"))
                    }
                    let cell = IssueRowCell(frame: NSRect(x: 0, y: 0, width: 900, height: Theme.rowHeight))
                    cell.appearance = NSApp.effectiveAppearance
                    cell.configure(IssueRowModel(
                        item: item, glyph: model.glyph(of: item), priority: model.priorityLevel(of: item),
                        showsPriority: model.project(of: item)?.priorityFieldId != nil
                    ), highlighted: false)
                    cell.hoveredPart = kind
                    if let rep = cell.bitmapImageRepForCachingDisplay(in: cell.bounds) {
                        cell.appearance?.performAsCurrentDrawingAppearance { cell.cacheDisplay(in: cell.bounds, to: rep) }
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(base).row-\(number)-\(name).png"))
                    }
                }
            }
            log("rendered hover states")
        case "comment":
            if let item = model.openItem { model.addComment(to: item, body: argument) }
        case "notice":
            model.status.post(Notice(title: "Test notice", message: argument))
        case "notify":
            // notify <start|done|tomorrow|open> <number>: answers a due-date notification as if it had been tapped.
            let bits = argument.split(separator: " ").map(String.init)
            if bits.count == 2, let item = item(bits[1], model) {
                let action = bits[0] == "open" ? "com.apple.UNNotificationDefaultActionIdentifier" : bits[0]
                Task { await Notifier.shared.handle(action: action, userInfo: [Notifier.Key.itemId: item.id, Notifier.Key.contentId: item.contentId ?? ""]) }
            }
        default:
            break
        }
    }

    /// Moves a card along a straight path with eased timing, the way a hand would.
    private static func drag(_ item: Item, toColumn name: String, index: Int, hold: Bool, model: AppModel) {
        let drag = model.boardDrag
        guard let from = drag.cardFrames[item.id],
              let column = model.columns.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }),
              let columnFrame = drag.columnFrames[column.id] else { return }
        let others = column.items.filter { $0.id != item.id }
        var y = columnFrame.minY + 40 + from.height / 2
        if index < others.count, let frame = drag.cardFrames[others[index].id] {
            y = frame.minY + 6
        } else if let last = others.last, let frame = drag.cardFrames[last.id] {
            y = frame.maxY + from.height / 2
        }
        let start = CGPoint(x: from.midX, y: from.midY)
        let end = CGPoint(x: columnFrame.midX, y: y)
        log("drag \(item.displayNumber) from \(start) to \(end) column=\(columnFrame)")
        var step = 0
        let steps = 36
        var previous = start
        dragTimer?.invalidate()
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            MainActor.assumeIsolated {
                step += 1
                let t = min(Double(step) / Double(steps), 1)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                let point = CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased)
                let velocity = CGSize(width: (point.x - previous.x) * 60, height: (point.y - previous.y) * 60)
                previous = point
                drag.changed(location: point, start: start, velocity: velocity, model: model)
                if step >= steps {
                    timer.invalidate()
                    if !hold { drag.ended(model: model) }
                }
            }
        }
    }

    /// Scrolls the tallest scroll view top to bottom in fixed steps and reports how long each step
    /// keeps the main thread busy. A step over 8 ms would drop a frame on a 120 Hz display.
    private static func scrollTest(label: String) {
        guard let root = NSApp.windows.first(where: { $0.isVisible })?.contentView else { return }
        var views: [NSScrollView] = []
        func collect(_ view: NSView) {
            if let scroll = view as? NSScrollView { views.append(scroll) }
            view.subviews.forEach(collect)
        }
        collect(root)
        guard let scrollView = views.max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
              let document = scrollView.documentView else {
            log("scrolltest: no scroll view")
            return
        }
        let clip = scrollView.contentView
        var times: [Double] = []
        var y: CGFloat = 0
        let step: CGFloat = 40
        var steps = 0
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            MainActor.assumeIsolated {
                let limit = max(0, document.frame.height - clip.bounds.height)
                let start = CACurrentMediaTime()
                y = min(y + step, limit)
                clip.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(clip)
                root.layoutSubtreeIfNeeded()
                root.displayIfNeeded()
                CATransaction.flush()
                times.append((CACurrentMediaTime() - start) * 1000)
                steps += 1
                if y >= limit || steps > 600 {
                    timer.invalidate()
                    let sorted = times.sorted()
                    let average = times.reduce(0, +) / Double(max(times.count, 1))
                    let p95 = sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.95)]
                    log(String(
                        format: "scrolltest %@: %d steps over %.0f pt, avg %.1f ms, p95 %.1f ms, max %.1f ms, over 8 ms: %d, over 16 ms: %d",
                        label, times.count, limit, average, p95, sorted.last ?? 0,
                        times.filter { $0 > 8 }.count, times.filter { $0 > 16 }.count
                    ))
                }
            }
        }
    }

    private static func findDescription(in view: NSView?) -> MarkdownTextView? {
        guard let view else { return nil }
        if let editor = view as? MarkdownTextView { return editor }
        for subview in view.subviews {
            if let found = findDescription(in: subview) { return found }
        }
        return nil
    }

    private static func click(at point: CGPoint, right: Bool = false) {
        guard let main = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 }),
              let content = main.contentView else { return }
        // The point is given in the main window; the click goes to whichever window is on top there,
        // such as an open dropdown.
        let inMain = CGPoint(x: point.x, y: content.bounds.height - point.y)
        let onScreen = main.convertPoint(toScreen: inMain)
        // Front to back, panels included (`orderedWindows` leaves them out).
        let numbers = NSWindow.windowNumbers(options: []) ?? []
        let window = numbers.lazy.compactMap { NSApp.window(withWindowNumber: $0.intValue) }
            .first { $0.isVisible && $0.frame.contains(onScreen) } ?? main
        let location = window.convertPoint(fromScreen: onScreen)
        log("click \(Int(point.x)),\(Int(point.y)) -> \(type(of: window)) at \(Int(location.x)),\(Int(location.y)); key=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil") active=\(NSApp.isActive)")
        let types: [NSEvent.EventType] = right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        let events = types.compactMap { type in
            NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown || type == .rightMouseDown ? 1 : 0
            )
        }
        guard events.count == 2 else { return }
        // AppKit controls track the mouse in a loop that reads the queue until the button comes up,
        // so the release waits in the queue before the press is sent.
        NSApp.postEvent(events[1], atStart: false)
        NSApp.sendEvent(events[0])
    }

    private static func sendKeys(_ text: String) {
        for character in text {
            sendKey(characters: String(character), code: 0)
        }
    }

    private static func sendKey(characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        // To the key window, as a real key press would go: a dropdown if one is open.
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
        if let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ) {
            NSApp.sendEvent(event)
        }
    }
}
#endif
#endif
