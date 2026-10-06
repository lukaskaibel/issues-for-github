#if os(macOS)
import AppKit
import SwiftUI

/// A Linear-style dropdown: a floating panel without an arrow that opens right under what was clicked,
/// takes the keyboard straight away, and closes when you pick, press Escape or click elsewhere.
/// A dropdown opened from inside another one stacks on top of it, such as a status picker for one row of the
/// sub-issue list; closing it hands the keyboard back to the one underneath.
@MainActor
enum Dropdown {
    /// Open dropdowns, the first opened from a window and each further one from the one before.
    private static var panels: [DropdownPanel] = []

    static var isOpen: Bool { !panels.isEmpty }

    #if DEBUG
    /// Set by the debug remote to follow what dropdowns do.
    static var trace: ((String) -> Void)?
    #else
    static let trace: ((String) -> Void)? = nil
    #endif

    /// Opens a dropdown at `rect`, given in `view`'s coordinates: under it, over it, or beside it as a submenu.
    /// From a view inside an open dropdown it opens on top of that one; from anywhere else it replaces whatever
    /// is open.
    @discardableResult
    static func show<Content: View>(
        below rect: NSRect, in view: NSView, model: AppModel, placement: DropdownPlacement = .below,
        onClose: @escaping () -> Void = {},
        @ViewBuilder content: (_ close: @escaping () -> Void) -> Content
    ) -> DropdownPanel? {
        guard let window = view.window else { return nil }
        if let host = window as? DropdownPanel, let index = panels.firstIndex(where: { $0 === host }) {
            close(from: index + 1)
        } else {
            close()
        }
        let handle = PanelHandle()
        let close: () -> Void = { if let panel = handle.panel { Dropdown.close(panel) } }
        let root = content(close)
            .environment(model)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.popover))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .fixedSize()
        let hosting = ResizingHostingView(rootView: root)
        let size = hosting.fittingSize

        let anchor = window.convertToScreen(view.convert(rect, to: nil))
        let screen = window.screen?.visibleFrame ?? .infinite
        var origin: NSPoint
        switch placement {
        case .below, .above:
            // Under the anchor, left edges aligned; above it when asked or when there's no room below.
            origin = NSPoint(x: anchor.minX - 4, y: anchor.minY - 4 - size.height)
            if placement == .above || origin.y < screen.minY { origin.y = anchor.maxY + 4 }
        case .trailing:
            // Right of the row, its first row level with it (the panel has 4 pt above its rows); left of it
            // when there's no room on the right.
            origin = NSPoint(x: anchor.maxX + 6, y: anchor.maxY + 4 - size.height)
            if origin.x + size.width > screen.maxX { origin.x = anchor.minX - 6 - size.width }
            origin.y = max(origin.y, screen.minY + 8)
        }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)

        let panel = DropdownPanel(contentRect: NSRect(origin: origin, size: size))
        handle.panel = panel
        let opensUpward = origin.y > anchor.minY
        hosting.onFittingSizeChange = { [weak panel] fitting in
            guard let panel, fitting.height > 0 else { return }
            var frame = panel.frame
            // Keep the edge next to what was clicked where it is.
            if !opensUpward { frame.origin.y = frame.maxY - fitting.height }
            frame.size = fitting
            panel.setFrame(frame, display: true)
        }
        panel.contentView = hosting
        panel.appearance = window.effectiveAppearance
        panel.onClose = onClose
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panels.append(panel)
        trace?("show: \(panels.count) open, nested=\(window is DropdownPanel)")
        return panel
    }

    /// Closes every open dropdown.
    static func close() {
        close(from: 0)
    }

    /// Closes this dropdown and any opened from it.
    static func close(_ panel: DropdownPanel) {
        if let index = panels.firstIndex(where: { $0 === panel }) { close(from: index) }
    }

    private static func close(from index: Int) {
        guard panels.indices.contains(index) else { return }
        trace?("close from \(index) of \(panels.count)")
        let closing = panels[index...].reversed()
        let underneath = panels[index].parent
        panels.removeSubrange(index...)
        for panel in closing {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.onClose()
        }
        // Back to what the dropdown was opened from, so its keys work again.
        if let underneath, underneath.isVisible { underneath.makeKey() }
    }

    fileprivate static func panelDidResignKey(_ resigned: DropdownPanel) {
        // The new key window is known only once AppKit has finished switching.
        DispatchQueue.main.async {
            guard let index = panels.firstIndex(where: { $0 === resigned }) else { return }
            let key = NSApp.keyWindow
            trace?("resigned \(index); key is \(key.map { String(describing: type(of: $0)) } ?? "nil") at \(panels.firstIndex(where: { $0 === key }).map(String.init) ?? "-")")
            if let keyIndex = panels.firstIndex(where: { $0 === key }) {
                // A click back in a dropdown further down closes the ones on top of it.
                if keyIndex < index { close(from: keyIndex + 1) }
            } else {
                // A click anywhere else closes them all, as a menu would.
                close()
            }
        }
    }
}

/// Where a dropdown opens relative to what was clicked.
enum DropdownPlacement {
    /// Under it, or over it when there's no room below.
    case below
    /// Over it, for things at the bottom of the window.
    case above
    /// To its right, as a submenu of a menu row.
    case trailing
}

private final class PanelHandle {
    weak var panel: DropdownPanel?
}

/// A hosting view that reports when its content wants a different size.
final class ResizingHostingView<Content: View>: NSHostingView<Content> {
    var onFittingSizeChange: ((NSSize) -> Void)?
    private var lastSize: NSSize = .zero

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        let size = fittingSize
        guard size != lastSize else { return }
        lastSize = size
        DispatchQueue.main.async { [weak self] in self?.onFittingSizeChange?(size) }
    }
}

final class DropdownPanel: NSPanel {
    var onClose: () -> Void = {}

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Clicking anywhere else closes it, as a menu would.
    override func resignKey() {
        super.resignKey()
        MainActor.assumeIsolated { Dropdown.panelDidResignKey(self) }
    }

    /// Escape, when nothing inside handled it.
    override func cancelOperation(_ sender: Any?) {
        MainActor.assumeIsolated { Dropdown.close(self) }
    }
}

// MARK: - SwiftUI

extension View {
    /// Shows a dropdown under this view while `isPresented` is true, or over it or beside it.
    func dropdown<Content: View>(
        isPresented: Binding<Bool>, placement: DropdownPlacement = .below,
        @ViewBuilder content: @escaping (_ close: @escaping () -> Void) -> Content
    ) -> some View {
        modifier(DropdownModifier(isPresented: isPresented, placement: placement, dropdownContent: content))
    }
}

private struct DropdownModifier<DropdownContent: View>: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    var placement: DropdownPlacement
    var dropdownContent: (_ close: @escaping () -> Void) -> DropdownContent

    func body(content: Content) -> some View {
        content.background(
            DropdownAnchor(isPresented: $isPresented, model: model, placement: placement, content: dropdownContent)
        )
    }
}

private struct DropdownAnchor<DropdownContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var model: AppModel
    var placement: DropdownPlacement
    var content: (_ close: @escaping () -> Void) -> DropdownContent

    func makeNSView(context: Context) -> PassthroughView { PassthroughView() }

    func updateNSView(_ view: PassthroughView, context: Context) {
        if isPresented, !view.isShowing {
            view.isShowing = true
            let binding = $isPresented
            view.panel = Dropdown.show(below: view.bounds, in: view, model: model, placement: placement, onClose: { [weak view] in
                view?.isShowing = false
                binding.wrappedValue = false
            }, content: content)
        } else if !isPresented, view.isShowing, let panel = view.panel {
            Dropdown.close(panel)
        }
    }
}

/// A view that is never the target of a click, for anchoring and measuring.
final class PassthroughView: NSView {
    var isShowing = false
    weak var panel: DropdownPanel?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Right-click menus for SwiftUI areas, shown as AppKit menus with icons. SwiftUI views register the
/// window frame they cover; one event monitor finds the innermost area under a right-click and shows its
/// menu. This avoids layering AppKit views over SwiftUI, which doesn't pass them clicks reliably.
@MainActor
final class ContextMenus {
    static let shared = ContextMenus()

    private var regions: [UUID: (frame: CGRect, menu: (CGPoint) -> NSMenu?)] = [:]

    /// `frame` is in window coordinates with the origin at the top left, as SwiftUI's `.global` space.
    func register(_ id: UUID, frame: CGRect, menu: @escaping (CGPoint) -> NSMenu?) {
        regions[id] = (frame, menu)
    }

    func remove(_ id: UUID) {
        regions[id] = nil
    }

    /// The menu of the smallest registered area containing the point, if it offers one there.
    func menu(at point: CGPoint) -> NSMenu? {
        let candidates = regions.values
            .filter { $0.frame.contains(point) }
            .sorted { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        for candidate in candidates {
            if let menu = candidate.menu(point) { return menu }
        }
        return nil
    }

    static func isContextClick(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }
}

extension AppModel {
    /// Opens the picker for one property of an issue under `rect`, given in window coordinates with the
    /// origin at the top left.
    func showPicker(_ kind: PickerKind, for item: Item, below rect: CGRect) {
        guard let content = mainWindow?.contentView else { return }
        let anchor = content.isFlipped ? rect : CGRect(x: rect.minX, y: content.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        Dropdown.show(below: anchor, in: content, model: self) { close in
            ItemPicker(kind: kind, itemId: item.id, close: close)
        }
    }
}
#endif
