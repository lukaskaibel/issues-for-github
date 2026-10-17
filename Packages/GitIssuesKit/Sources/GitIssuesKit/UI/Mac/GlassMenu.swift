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
    @State private var active: Int?
    @State private var openSubmenu: Int?
    @FocusState private var focused: Bool

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
                        guard query.isEmpty, let active, rows.indices.contains(active), rows[active].item.hasSubmenu else { return .ignored }
                        openSubmenu = active
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
                    .onSubmit {
                        if let active, rows.indices.contains(active) { activate(rows[active], index: active) }
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
        .padding(.bottom, 6)
        .frame(width: 272)
        .font(.ui)
        .foregroundStyle(Theme.text)
        .onChange(of: query) {
            openSubmenu = nil
            active = query.isEmpty ? nil : rows.firstIndex { $0.item.isEnabled && !$0.item.isSeparatorItem && $0.item.action != nil }
        }
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
            GlassMenuRow(entry: entry, active: active == index || openSubmenu == index) {
                activate(entry, index: index)
            } onHover: { inside in
                guard inside else { return }
                active = index
                // Another row of this menu closes the submenu that is open; moving into the submenu keeps it.
                if openSubmenu != index { openSubmenu = item.hasSubmenu && query.isEmpty ? index : nil }
            }
            .dropdown(isPresented: Binding(
                get: { openSubmenu == index && query.isEmpty },
                set: { open in if !open, openSubmenu == index { openSubmenu = nil } }
            ), placement: .trailing) { closeSubmenu in
                submenu(of: item, close: closeSubmenu)
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

    private func activate(_ entry: Entry, index: Int) {
        let item = entry.item
        guard item.isEnabled else { return }
        if item.hasSubmenu {
            openSubmenu = index
            return
        }
        // Everything closes first, as with a menu, so what the entry opens (a dialog, the palette) gets the keyboard.
        Dropdown.close()
        GlassMenu.perform(item)
    }

    private func move(_ delta: Int, in rows: [Entry]) {
        let usable = rows.indices.filter { rows[$0].item.isEnabled && !rows[$0].item.isSeparatorItem && (rows[$0].item.action != nil || rows[$0].item.hasSubmenu) }
        guard !usable.isEmpty else { return }
        let position = active.flatMap { usable.firstIndex(of: $0) }
        let next = menuStep(position, by: delta, count: usable.count) ?? 0
        active = usable[next]
        openSubmenu = nil
    }
}

/// An entry of a glass menu: its icon, its title (with the submenus it is in, when found by searching), and on the
/// right a checkmark, its keys or the arrow of a submenu.
private struct GlassMenuRow: View {
    let entry: GlassMenuView.Entry
    var active: Bool
    var action: () -> Void
    var onHover: (Bool) -> Void

    var body: some View {
        let item = entry.item
        Button(action: action) {
            HStack(spacing: 9) {
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
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active && item.isEnabled ? Theme.menuHighlight : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.45)
        .padding(.horizontal, 6)
        .help(item.toolTip ?? "")
        .onHover(perform: onHover)
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
