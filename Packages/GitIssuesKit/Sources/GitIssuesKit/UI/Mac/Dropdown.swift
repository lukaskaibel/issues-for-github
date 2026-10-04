#if os(macOS)
import AppKit
import SwiftUI

/// A Linear-style dropdown: a floating panel without an arrow that opens right under what was clicked,
/// takes the keyboard straight away, and closes when you pick, press Escape or click elsewhere.
/// Only one is open at a time.
@MainActor
enum Dropdown {
    private static var panel: DropdownPanel?

    static var isOpen: Bool { panel != nil }

    /// Opens a dropdown under `rect`, given in `view`'s coordinates.
    static func show<Content: View>(
        below rect: NSRect, in view: NSView, model: AppModel, onClose: @escaping () -> Void = {},
        @ViewBuilder content: (_ close: @escaping () -> Void) -> Content
    ) {
        close()
        guard let window = view.window else { return }
        let close: () -> Void = { Dropdown.close() }
        let root = content(close)
            .environment(model)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.popover))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.popoverBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .fixedSize()
        let hosting = ResizingHostingView(rootView: root)
        let size = hosting.fittingSize

        // Under the anchor, left edges aligned; above it when there's no room below.
        let anchor = window.convertToScreen(view.convert(rect, to: nil))
        let screen = window.screen?.visibleFrame ?? .infinite
        var origin = NSPoint(x: anchor.minX - 4, y: anchor.minY - 4 - size.height)
        if origin.y < screen.minY { origin.y = anchor.maxY + 4 }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)

        let panel = DropdownPanel(contentRect: NSRect(origin: origin, size: size))
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
        self.panel = panel
    }

    static func close() {
        guard let panel else { return }
        self.panel = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.onClose()
        // Back to the main window, so its shortcuts work again.
        panel.parent?.makeKey()
    }

    fileprivate static func panelDidResignKey(_ resigned: DropdownPanel) {
        if resigned === panel { close() }
    }
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
        MainActor.assumeIsolated { Dropdown.close() }
    }
}

// MARK: - SwiftUI

extension View {
    /// Shows a dropdown under this view while `isPresented` is true.
    func dropdown<Content: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping (_ close: @escaping () -> Void) -> Content
    ) -> some View {
        modifier(DropdownModifier(isPresented: isPresented, dropdownContent: content))
    }
}

private struct DropdownModifier<DropdownContent: View>: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    var dropdownContent: (_ close: @escaping () -> Void) -> DropdownContent

    func body(content: Content) -> some View {
        content.background(
            DropdownAnchor(isPresented: $isPresented, model: model, content: dropdownContent)
        )
    }
}

private struct DropdownAnchor<DropdownContent: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var model: AppModel
    var content: (_ close: @escaping () -> Void) -> DropdownContent

    func makeNSView(context: Context) -> PassthroughView { PassthroughView() }

    func updateNSView(_ view: PassthroughView, context: Context) {
        if isPresented, !view.isShowing {
            view.isShowing = true
            let binding = $isPresented
            Dropdown.show(below: view.bounds, in: view, model: model, onClose: { [weak view] in
                view?.isShowing = false
                binding.wrappedValue = false
            }, content: content)
        } else if !isPresented, view.isShowing {
            Dropdown.close()
        }
    }
}

/// A view that is never the target of a click, for anchoring and measuring.
final class PassthroughView: NSView {
    var isShowing = false
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
