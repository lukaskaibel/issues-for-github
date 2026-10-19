#if os(iOS)
import SwiftUI
import UIKit

extension View {
    /// A key for the screen this view is on, with a keyboard, that goes before text input: ⌘↵ creates an issue
    /// or sends a comment even while the cursor is in a text field, which would otherwise read it as a plain
    /// Return. `keyboardShortcut` can't do that. Applies while `isActive`.
    func screenKey(_ title: LocalizedStringResource, _ input: String, modifiers: UIKeyModifierFlags = [], isActive: Bool = true, action: @escaping () -> Void) -> some View {
        background {
            if isActive {
                ScreenKeyCommand(title: String(localized: title), input: input, modifiers: modifiers, action: action)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Escape for a mode of the screen that nothing is typed into, such as picking sub-issues. Key commands reach a
    /// screen only through what has the keyboard's attention, so while `isActive` an invisible view on the screen
    /// takes it, and holds Escape before the system does.
    func escapeKey(isActive: Bool, action: @escaping () -> Void) -> some View {
        background {
            if isActive {
                EscapeKeyView(action: action)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct EscapeKeyView: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> Responder {
        let view = Responder()
        view.action = action
        return view
    }

    func updateUIView(_ view: Responder, context: Context) {
        view.action = action
    }

    final class Responder: UIView {
        var action: () -> Void = {}

        override var canBecomeFirstResponder: Bool { true }

        override var keyCommands: [UIKeyCommand]? {
            let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapePressed))
            escape.wantsPriorityOverSystemBehavior = true
            return [escape]
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // Once on screen; a text field that has the cursor keeps it.
            Task { @MainActor [weak self] in
                guard let self, self.window != nil, !(self.window?.firstResponderIsTextInput ?? false) else { return }
                self.becomeFirstResponder()
            }
        }

        @objc private func escapePressed() {
            action()
        }
    }
}

private extension UIWindow {
    var firstResponderIsTextInput: Bool {
        var found: UIResponder?
        func search(_ view: UIView) {
            if found != nil { return }
            if view.isFirstResponder { found = view; return }
            view.subviews.forEach(search)
        }
        search(self)
        return found is UITextInput
    }
}

/// Puts a key command on the controller showing the screen, which the text fields on it report to.
private struct ScreenKeyCommand: UIViewControllerRepresentable {
    var title: String
    var input: String
    var modifiers: UIKeyModifierFlags
    var action: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(command: UIKeyCommand(title: title, action: #selector(UIViewController.giScreenKey(_:)), input: input, modifierFlags: modifiers), action: action)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.action = action
    }

    final class Controller: UIViewController {
        let command: UIKeyCommand
        var action: () -> Void
        private weak var host: UIViewController?

        init(command: UIKeyCommand, action: @escaping () -> Void) {
            command.wantsPriorityOverSystemBehavior = true
            self.command = command
            self.action = action
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Not used") }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            uninstall()
            guard let parent else { return }
            parent.addKeyCommand(command)
            ScreenKeys.handlers[ScreenKeys.Key(parent, command)] = { [weak self] in self?.action() }
            host = parent
        }

        private func uninstall() {
            guard let host else { return }
            host.removeKeyCommand(command)
            ScreenKeys.handlers[ScreenKeys.Key(host, command)] = nil
            self.host = nil
        }

        isolated deinit {
            uninstall()
        }
    }
}

@MainActor
private enum ScreenKeys {
    struct Key: Hashable {
        var host: ObjectIdentifier
        var input: String
        var modifiers: Int

        @MainActor
        init(_ host: UIViewController, _ command: UIKeyCommand) {
            self.host = ObjectIdentifier(host)
            input = command.input ?? ""
            modifiers = command.modifierFlags.rawValue
        }
    }

    static var handlers: [Key: () -> Void] = [:]
}

extension UIViewController {
    /// Runs the action of a screen key, on this screen or the nearest one around it that has it.
    @objc fileprivate func giScreenKey(_ sender: UIKeyCommand) {
        var controller: UIViewController? = self
        while let current = controller {
            if let handler = ScreenKeys.handlers[ScreenKeys.Key(current, sender)] {
                handler()
                return
            }
            controller = current.parent
        }
    }
}
#endif
