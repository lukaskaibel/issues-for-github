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
