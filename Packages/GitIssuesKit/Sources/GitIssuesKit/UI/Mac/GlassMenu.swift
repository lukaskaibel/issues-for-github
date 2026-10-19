#if os(macOS)
import AppKit
import SwiftUI

/// Right-click menus, drawn like the pickers instead of as the system's small menus: glass, rows as tall as a
/// picker's, the keys beside each entry, and a field to type in that finds any entry, also inside a submenu.
/// The entries are the app's AppKit menus, so each does exactly what it did; a submenu that is a property of an
/// issue (status, priority, assignees, labels, due date, milestone) opens that property's picker itself.
@MainActor
enum GlassMenu {
    /// Opens `menu` where `event` happened, with its top left corner at the pointer, as a menu would.
    static func show(_ menu: NSMenu, at event: NSEvent, in view: NSView, model: AppModel) {
        let point = view.convert(event.locationInWindow, from: nil)
        let anchor = NSRect(x: point.x + 4, y: point.y + (view.isFlipped ? 4 : -4), width: 1, height: 1)
        Dropdown.show(below: anchor, in: view, model: model) { close in
            GlassMenuView(menu: menu, close: close)
        }
    }

    /// Runs an entry the way the menu would have.
    static func perform(_ item: NSMenuItem) {
        guard let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }
}

/// What a picker in a menu's submenu is for: which property of which issue.
final class PickerMenuTarget: NSObject {
    let kind: PickerKind
    let itemId: String

    init(kind: PickerKind, itemId: String) {
        self.kind = kind
        self.itemId = itemId
    }
}

/// One menu, or a submenu, as a glass list.
struct GlassMenuView: View {
    @Environment(AppModel.self) private var model
    let menu: NSMenu
    var close: () -> Void

    @State private var query = ""
    @State private var cursor = MenuCursor<Int>()
    @State private var aim = SubmenuAim()
    @State private var frames = SubmenuFrames()
    @FocusState private var focused: Bool

    /// A submenu opens as soon as the pointer slows down on its row or moves sideways, toward it; passing over rows on
    /// the way to another opens nothing. Stopping dead sends no more moves, so after this long it opens anyway.
    static let openDelay: TimeInterval = 0.06
    /// How long a submenu waits for the pointer heading to it across other rows.
    static let aimPatience: TimeInterval = 0.25

    /// An entry as drawn: a row of this menu, or when searching, an entry anywhere below it with the path to it.
    struct Entry: Identifiable {
        let id: Int
        let item: NSMenuItem
        /// The submenus it is in when found by searching ("Status").
        var path: [String] = []
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField(String(localized: .contextMenuSearchPlaceholder), text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .focusOnAppear()
                    .onKeyPress(.downArrow) {
                        move(1, in: rows)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        move(-1, in: rows)
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        guard query.isEmpty, let active = cursor.key, rows.indices.contains(active), rows[active].item.hasSubmenu else { return .ignored }
                        openSubmenu(active, withKeys: true)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
                    .onSubmit {
                        if let active = cursor.key, rows.indices.contains(active) { activate(rows[active], index: active, withKeys: true) }
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.field))
            .padding([.horizontal, .top], 6)
            .padding(.bottom, 4)

            if rows.isEmpty {
                Text(.noMatches)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 15)
                    .frame(height: PickerRow.height)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                row(entry, index: index)
            }
        }
        .coordinateSpace(.named(SubmenuFrames.space))
        .overlay(alignment: .topLeading) {
            SubmenuSlot(cursor: cursor, frames: frames) { index, closeSubmenu in
                if rows.indices.contains(index) { submenu(of: rows[index].item, close: closeSubmenu) }
            }
        }
        .padding(.bottom, 6)
        .frame(width: 272)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onContinuousHover(coordinateSpace: .named(SubmenuFrames.space)) { phase in
            guard case .active(let point) = phase else { return }
            aim.record(point)
            if aim.isWaiting {
                // Turned away from the open submenu, or stopped short of it: the row under the pointer lights at once.
                if !aim.headsForSubmenu() { settle() }
            } else if aim.opening != nil, aim.settles {
                openPending()
            }
        }
        .background(WindowReader { aim.home = $0 })
        .onChange(of: query) {
            aim.cancel()
            cursor.open = nil
            cursor.key = query.isEmpty ? nil : rows.firstIndex { $0.item.isEnabled && !$0.item.isSeparatorItem && $0.item.action != nil }
        }
        .onDisappear { aim.cancel() }
    }

    /// The menu's entries, or while searching the ones anywhere in it that match.
    private var rows: [Entry] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return menu.items.enumerated().filter { !$0.element.isHidden }.map { Entry(id: $0.offset, item: $0.element) }
        }
        var found: [Entry] = []
        func search(_ menu: NSMenu, path: [String]) {
            for item in menu.items where !item.isHidden && !item.isSeparatorItem {
                if let submenu = item.submenu {
                    search(submenu, path: path + [item.title])
                } else if item.isEnabled, item.action != nil {
                    let haystack = (path + [item.title]).joined(separator: " ").lowercased()
                    if words.allSatisfy(haystack.contains) {
                        found.append(Entry(id: found.count, item: item, path: path))
                    }
                }
            }
        }
        search(menu, path: [])
        return Array(found.prefix(14))
    }

    @ViewBuilder
    private func row(_ entry: Entry, index: Int) -> some View {
        let item = entry.item
        if item.isSeparatorItem {
            MenuDivider()
        } else if !item.isEnabled, item.action == nil, item.submenu == nil {
            // A title, such as how many issues the menu acts on.
            Text(item.title)
                .font(.tinySemibold)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 15)
                .padding(.top, 4)
                .padding(.bottom, 2)
        } else {
            GlassMenuRow(entry: entry, index: index, cursor: cursor, frames: frames) {
                activate(entry, index: index, withKeys: false)
            } onHover: { inside in
                hover(index, inside)
            }
        }
    }

    @ViewBuilder
    private func submenu(of item: NSMenuItem, close closeSubmenu: @escaping () -> Void) -> some View {
        if let target = item.representedObject as? PickerMenuTarget, model.item(id: target.itemId) != nil {
            // The property's own picker, ready to type in, as a click on the card would open it.
            ItemPicker(kind: target.kind, itemId: target.itemId) {
                closeSubmenu()
                close()
            }
        } else if let submenu = item.submenu {
            GlassMenuView(menu: submenu) {
                closeSubmenu()
            }
        }
    }

    // MARK: Pointer

    private func hover(_ index: Int, _ inside: Bool) {
        guard inside else {
            if aim.hovered == index { aim.hovered = nil }
            return
        }
        aim.hovered = index
        if let open = cursor.open, open != index, aim.headsForSubmenu() {
            // On the way to the open submenu across this row: it stays, and the row lights only if the pointer
            // settles here.
            aim.wait(Self.aimPatience) { settle() }
            return
        }
        lightUp(index)
    }

    /// Lights the row under the pointer, closes another row's submenu and opens the row's own after a moment's rest.
    private func lightUp(_ index: Int) {
        aim.cancel()
        cursor.key = index
        let closes = cursor.open != nil && cursor.open != index
        if closes { cursor.open = nil }
        let rows = rows
        guard query.isEmpty, rows.indices.contains(index), rows[index].item.hasSubmenu, rows[index].item.isEnabled,
              cursor.open != index else { return }
        aim.later(Self.openDelay) { openWhenResting() }
        aim.opening = index
        // Not in the same moment another closes: the one place submenus open from has to see it closed first.
        if aim.settles, !closes { openPending() }
    }

    /// The pointer sends no moves once it stops; still moving quickly, it may be on its way to another row.
    private func openWhenResting() {
        guard let index = aim.opening else { return }
        if aim.isMoving, !aim.settles {
            aim.later(Self.openDelay) { openWhenResting() }
            aim.opening = index
        } else {
            openPending()
        }
    }

    /// Opens the submenu the pointer slowed down on.
    private func openPending() {
        guard let index = aim.opening, aim.hovered == index, cursor.open == nil else { return }
        aim.cancel()
        cursor.openSubmenu(index, takesKey: false)
    }

    /// After the pointer headed for the open submenu: in it, the submenu's row stays lit; anywhere else in this menu,
    /// the row there lights up.
    private func settle() {
        if aim.pointerInSubmenu() {
            aim.cancel()
            cursor.key = cursor.open
        } else if let index = aim.hovered {
            lightUp(index)
        } else {
            aim.cancel()
        }
    }

    // MARK: Keys and clicks

    private func activate(_ entry: Entry, index: Int, withKeys: Bool) {
        let item = entry.item
        guard item.isEnabled else { return }
        if item.hasSubmenu {
            openSubmenu(index, withKeys: withKeys)
            return
        }
        // Everything closes first, as with a menu, so what the entry opens (a dialog, the palette) gets the keyboard.
        Dropdown.close()
        GlassMenu.perform(item)
    }

    /// Opens a row's submenu at once; from the keys, the submenu takes the keyboard, also when it is already open.
    private func openSubmenu(_ index: Int, withKeys: Bool) {
        aim.cancel()
        cursor.key = index
        if cursor.open == index {
            if withKeys, let menu = NSApp.keyWindow { Dropdown.focusPanel(openedFrom: menu) }
        } else if cursor.open != nil {
            // Another row's submenu closes first, so the one place submenus open from sees it open anew.
            cursor.open = nil
            DispatchQueue.main.async { cursor.openSubmenu(index, takesKey: withKeys) }
        } else {
            cursor.openSubmenu(index, takesKey: withKeys)
        }
    }

    private func move(_ delta: Int, in rows: [Entry]) {
        let usable = rows.indices.filter { rows[$0].item.isEnabled && !rows[$0].item.isSeparatorItem && (rows[$0].item.action != nil || rows[$0].item.hasSubmenu) }
        aim.cancel()
        cursor.open = nil
        cursor.step(delta, through: usable)
    }
}

/// The frames of a menu's rows that have a submenu, in the menu's own space. Plain bookkeeping, read when a submenu
/// opens, so rows putting them down redraws nothing.
@MainActor
private final class SubmenuFrames {
    static let space = "glassMenu"
    var rects: [Int: CGRect] = [:]
}

/// Where a glass menu's submenu opens: beside the row whose submenu is open. One for the whole menu, in place of one
/// for every row with a submenu, each of which was an AppKit view to set up when the menu opened.
private struct SubmenuSlot<Content: View>: View {
    let cursor: MenuCursor<Int>
    let frames: SubmenuFrames
    @ViewBuilder var content: (_ index: Int, _ close: @escaping () -> Void) -> Content

    var body: some View {
        let open = cursor.open
        let frame = open.flatMap { frames.rects[$0] } ?? .zero
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .allowsHitTesting(false)
            .dropdown(isPresented: Binding(
                // Read when asked, not when drawn: a submenu that closes itself is asked about before this is redrawn.
                get: { cursor.open != nil },
                set: { isOpen in if !isOpen, cursor.open == open { cursor.open = nil } }
            ), placement: .trailing, takesKey: cursor.openTakesKey) { close in
                if let open = cursor.open { content(open, close) }
            }
            .padding(.leading, frame.minX)
            .padding(.top, frame.minY)
    }
}

/// When a submenu opens and closes under the pointer, as a menu does it: once the pointer slows down on its row, so
/// passing over rows opens nothing, and not while the pointer crosses other rows on its way to the open submenu. Plain
/// bookkeeping, outside SwiftUI's state, so the pointer moving redraws nothing.
@MainActor
private final class SubmenuAim {
    /// Slower than this, in points a second, the pointer has arrived rather than passing by.
    static let slow: Double = 180

    /// The row under the pointer.
    var hovered: Int?
    /// The row whose submenu opens once the pointer settles on it.
    var opening: Int?
    /// The dropdown this menu is in.
    weak var home: NSWindow?
    /// Where the pointer was lately in the menu, from its top left, oldest first.
    private var trail: [(point: CGPoint, time: TimeInterval)] = []
    private var pending: DispatchWorkItem?
    /// Whether a submenu is kept open for the pointer heading to it.
    private(set) var isWaiting = false

    func record(_ point: CGPoint) {
        trail.append((point, ProcessInfo.processInfo.systemUptime))
        if trail.count > 4 { trail.removeFirst() }
    }

    /// Whether the pointer moved a moment ago.
    var isMoving: Bool {
        trail.last.map { ProcessInfo.processInfo.systemUptime - $0.time < 0.04 } ?? false
    }

    /// Slowing down, or moving sideways toward where submenus open rather than up or down to other rows.
    var settles: Bool {
        // Too few moves to tell: the timer opens it once the pointer stops.
        guard trail.count > 1, let from = trail.first, let to = trail.last, to.time > from.time else { return false }
        let dx = to.point.x - from.point.x, dy = to.point.y - from.point.y
        return hypot(dx, dy) / (to.time - from.time) < Self.slow || abs(dx) > 2 * abs(dy)
    }

    func later(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        cancel()
        let item = DispatchWorkItem(block: work)
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func wait(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        later(delay, work)
        isWaiting = true
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        opening = nil
        isWaiting = false
    }

    /// The open submenu, on screen.
    private var submenuFrame: NSRect? {
        home.flatMap { Dropdown.panel(openedFrom: $0) }?.frame
    }

    func pointerInSubmenu() -> Bool {
        submenuFrame?.contains(NSEvent.mouseLocation) ?? false
    }

    /// Whether the pointer moves into the triangle between where it was and the submenu's near edge: on its way there.
    func headsForSubmenu() -> Bool {
        guard let screen = submenuFrame, let menu = home?.frame, let from = trail.first?.point, let to = trail.last?.point, from != to else { return false }
        // The submenu in the menu's own space, which runs down from its top left as the trail does.
        let target = CGRect(x: screen.minX - menu.minX, y: menu.maxY - screen.maxY, width: screen.width, height: screen.height)
        let onRight = target.midX > menu.width / 2
        let edge = onRight ? target.minX : target.maxX
        // Moving away from the submenu's side is never on the way.
        guard onRight ? to.x > from.x : to.x < from.x else { return false }
        let top = CGPoint(x: edge, y: target.minY - 20)
        let bottom = CGPoint(x: edge, y: target.maxY + 20)
        func side(_ a: CGPoint, _ b: CGPoint, _ p: CGPoint) -> CGFloat {
            (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        }
        let s1 = side(from, top, to), s2 = side(top, bottom, to), s3 = side(bottom, from, to)
        return (s1 >= 0 && s2 >= 0 && s3 >= 0) || (s1 <= 0 && s2 <= 0 && s3 <= 0)
    }
}

/// An entry of a glass menu: its icon, its title (with the submenus it is in, when found by searching), and on the
/// right a checkmark, its keys or the arrow of a submenu. It asks the cursor only about itself, so the light moving
/// over the menu redraws two rows. A click runs it without a `Button`, which would give every row an AppKit view of its
/// own for the keyboard loop; the arrow keys in the search field move through the menu instead.
private struct GlassMenuRow: View {
    let entry: GlassMenuView.Entry
    let index: Int
    let cursor: MenuCursor<Int>
    /// Where rows with a submenu put down their frames, for the submenu to open beside them.
    let frames: SubmenuFrames
    var action: () -> Void
    var onHover: (Bool) -> Void

    var body: some View {
        let item = entry.item
        let row = HStack(spacing: 9) {
            icon(item.image)
                .frame(width: 16, height: 16)
            HStack(spacing: 5) {
                ForEach(entry.path, id: \.self) { step in
                    Text(step).foregroundStyle(Theme.textTertiary)
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textTertiary)
                }
                Text(item.title)
                    .foregroundStyle(isDestructive(item) ? Theme.blocked : Theme.text)
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            if item.state == .on {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            if let keys = keys(item) {
                Text(keys)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            if item.hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: PickerRow.height)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cursor.isLit(index) && item.isEnabled ? Theme.menuHighlight : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.45)
        .padding(.horizontal, 6)
        .optionalHelp(item.toolTip)
        .onHover(perform: onHover)
        if item.hasSubmenu {
            row.onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(SubmenuFrames.space))
            } action: { frame in
                frames.rects[index] = frame
            }
        } else {
            row
        }
    }

    @ViewBuilder
    private func icon(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: 15, maxHeight: 15)
        } else {
            Color.clear
        }
    }

    /// Delete and the like, which the AppKit menu shows in red.
    private func isDestructive(_ item: NSMenuItem) -> Bool {
        guard let title = item.attributedTitle, title.length > 0,
              let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor else { return false }
        return color == .systemRed
    }

    /// The keys as a menu writes them: "⇧⌘C", or a single key such as "S" or "1".
    private func keys(_ item: NSMenuItem) -> String? {
        let key = item.keyEquivalent
        guard !key.isEmpty else { return nil }
        var text = ""
        let mask = item.keyEquivalentModifierMask
        if mask.contains(.control) { text += "⌃" }
        if mask.contains(.option) { text += "⌥" }
        if mask.contains(.shift) { text += "⇧" }
        if mask.contains(.command) { text += "⌘" }
        switch key {
        case " ": text += String(localized: .spaceKeyCap)
        case "\u{8}", "\u{7F}": text += "⌫"
        case "\r": text += "↩"
        default: text += key.uppercased()
        }
        return text
    }
}
#endif

#if os(macOS)
// MARK: - Glass menus for SwiftUI views

extension View {
    /// The view's right-click menu, drawn in glass like every other menu of the app. The menu is built when it opens,
    /// from what the view shows then.
    func glassContextMenu(_ menu: @escaping () -> NSMenu?) -> some View {
        modifier(GlassContextMenu(menu: menu))
    }

    /// The same for a row of the sidebar, whose menu covers the whole row and not just its label.
    func glassSidebarMenu(_ menu: @escaping () -> NSMenu?) -> some View {
        modifier(GlassContextMenu(menu: menu, outset: CGSize(width: 10, height: 8)))
    }

    /// A tooltip when there is one; without, none of the tracking that `.help("")` sets up for every row.
    @ViewBuilder
    func optionalHelp(_ text: String?) -> some View {
        if let text, !text.isEmpty { help(text) } else { self }
    }
}

private final class MenuSource {
    var build: () -> NSMenu? = { nil }
}

private struct GlassContextMenu: ViewModifier {
    var menu: () -> NSMenu?
    /// How far the menu reaches past the view on each side.
    var outset = CGSize.zero
    @State private var region = UUID()
    @State private var source = MenuSource()

    func body(content: Content) -> some View {
        // The latest closure, so the menu shows what the view shows now, not what it showed when it first appeared.
        source.build = menu
        return content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { [source, region, outset] frame in
                ContextMenus.shared.register(region, frame: frame.insetBy(dx: -outset.width, dy: -outset.height)) { _ in source.build() }
            }
            .onDisappear { [region] in ContextMenus.shared.remove(region) }
    }
}

/// A "⋯" button that opens a menu in glass under it, as a right-click would.
struct GlassMenuButton: View {
    var systemImage = "ellipsis"
    var label: LocalizedStringResource
    var size = CGSize(width: 32, height: 30)
    var menu: () -> NSMenu
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textBody)
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .dropdown(isPresented: $open) { close in
            GlassMenuView(menu: menu(), close: close)
        }
    }
}

/// Anything that opens a menu in glass under it when clicked, such as a chip to pick a project with.
struct GlassMenuPicker<Label: View>: View {
    var menu: () -> NSMenu
    @ViewBuilder var label: Label
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            label
        }
        .buttonStyle(PlainPressStyle())
        .dropdown(isPresented: $open) { close in
            GlassMenuView(menu: menu(), close: close)
        }
    }
}

/// Builds AppKit menus from closures, for the glass menus of SwiftUI views.
@MainActor
struct MenuBuilder {
    let menu = NSMenu()

    init() {
        menu.autoenablesItems = false
    }

    @discardableResult
    func item(_ title: LocalizedStringResource, _ symbol: String? = nil, checked: Bool = false, enabled: Bool = true, destructive: Bool = false, action: @escaping () -> Void) -> NSMenuItem {
        item(String(localized: title), symbol, checked: checked, enabled: enabled, destructive: destructive, action: action)
    }

    @discardableResult
    func item(_ title: String, _ symbol: String? = nil, image: NSImage? = nil, checked: Bool = false, enabled: Bool = true, destructive: Bool = false, action: @escaping () -> Void) -> NSMenuItem {
        let entry = ClosureMenuItem(title, checked: checked, handler: action)
        entry.image = image ?? symbol.flatMap(MenuIcons.symbol)
        entry.isEnabled = enabled
        if destructive, enabled {
            entry.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 0)])
        }
        menu.addItem(entry)
        return entry
    }

    func submenu(_ title: LocalizedStringResource, _ symbol: String?, _ build: (MenuBuilder) -> Void) {
        let sub = MenuBuilder()
        build(sub)
        let entry = NSMenuItem(title: String(localized: title), action: nil, keyEquivalent: "")
        entry.image = symbol.flatMap(MenuIcons.symbol)
        entry.submenu = sub.menu
        menu.addItem(entry)
    }

    func divider() {
        // No line first or twice in a row.
        guard let last = menu.items.last, !last.isSeparatorItem else { return }
        menu.addItem(.separator())
    }

    func build() -> NSMenu {
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        return menu
    }
}
#endif
