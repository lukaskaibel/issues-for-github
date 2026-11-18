import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Keeps `AppModel.textHasKeyboard` up to date, which decides whether ⌘Z is about the text being typed or about the app.
@MainActor
final class TextKeyboardWatcher {
    private weak var model: AppModel?
    private var tokens: [NSObjectProtocol] = []
    #if os(macOS)
    private var responder: NSKeyValueObservation?
    #endif

    init(model: AppModel) {
        self.model = model
        let center = NotificationCenter.default
        #if os(macOS)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
        #else
        let began = [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification]
        let ended = [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification]
        for (names, editing) in [(began, true), (ended, false)] {
            for name in names {
                tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.set(editing) }
                })
            }
        }
        #endif
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }

    private func set(_ value: Bool) {
        if model?.textHasKeyboard != value { model?.textHasKeyboard = value }
    }

    #if os(macOS)
    /// Follows the window that has the keyboard, or the app's window while none does.
    func refresh() {
        responder = (NSApp.keyWindow ?? model?.mainWindow)?.observe(\.firstResponder, options: []) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    private func update() {
        if let model { set(model.keyboardIsWithText) }
    }
    #endif
}
