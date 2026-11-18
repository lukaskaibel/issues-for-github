import SwiftUI

/// One thing an undo step does when it runs.
enum UndoAction {
    /// Changes queued for GitHub like any other.
    case changes([Mutation])
    /// Something that isn't a queued change. It records its own opposite with `recordUndo`.
    case restore(@MainActor (AppModel) -> Void)
}

/// ⌘Z and ⇧⌘Z: one history of what was done in the app. Text being typed in keeps its own undo, which the commands go to
/// while it has the keyboard.
extension AppModel {
    // MARK: Recording

    /// Notes what takes back something just done. All that one key press or click does becomes one step.
    func recordUndo(_ action: UndoAction, name: LocalizedStringResource, tag: UUID? = nil, mergeKey: String? = nil) {
        let wasGrouping = undoHistory.isGrouping
        undoHistory.record([action], name: name, tag: tag, mergeKey: mergeKey)
        guard undoHistory.mode == .recording, !wasGrouping, undoHistory.isGrouping else { return }
        DispatchQueue.main.async { [weak self] in self?.undoHistory.endGroup() }
    }

    /// Records what takes `mutations` back, under the name of the first that has one.
    func recordUndo(of mutations: [Mutation], reversal: [Mutation]?) {
        guard let reversal, !reversal.isEmpty else { return }
        let name = mutations.lazy.compactMap(\.undoName).first ?? .actionChangeIssue
        // A description is saved again and again while it is written; undoing goes back to before all of it.
        var mergeKey: String?
        if mutations.count == 1, case .setBody(let body) = mutations[0] { mergeKey = "body:\(body.contentId)" }
        recordUndo(.changes(reversal), name: name, mergeKey: mergeKey)
    }

    /// Says what was just done, with a button that takes back exactly that.
    func postWithUndo(title: String, message: String) {
        var notice = Notice(title: title, message: message, action: .undo)
        if !undoHistory.tagLastStep(notice.id) { notice.action = nil }
        status.post(notice)
    }

    // MARK: Running

    func undo() { runNext(.undoing) }
    func redo() { runNext(.redoing) }

    /// The Undo button of a notice: takes back what the notice is about, even when something else was done since.
    func undo(_ notice: Notice) {
        status.dismiss(notice.id)
        guard let step = undoHistory.take(.undoing, tag: notice.id) else { return }
        _ = run(step, .undoing)
    }

    /// Takes back the Inbox change its message is about.
    func undoInbox() {
        guard let id = inboxUndo?.id, let step = undoHistory.take(.undoing, tag: id) else { return }
        _ = run(step, .undoing)
    }

    /// Runs the next step that still does something: one about an issue deleted since is passed over.
    private func runNext(_ mode: UndoHistory<UndoAction>.Mode) {
        while let step = undoHistory.take(mode) {
            guard run(step, mode) else { continue }
            if let tag = step.tag { status.dismiss(tag) }
            announce(step, mode)
            return
        }
    }

    private func run(_ step: UndoHistory<UndoAction>.Step, _ mode: UndoHistory<UndoAction>.Mode) -> Bool {
        undoHistory.begin(mode, step)
        withAnimation(Theme.spring) {
            for action in step.actions {
                switch action {
                case .changes(let mutations): perform(mutations)
                case .restore(let restore): restore(self)
                }
            }
        }
        return undoHistory.finish()
    }

    /// Says what the key did, since it may have happened out of sight. One message at a time, however often it is pressed.
    private func announce(_ step: UndoHistory<UndoAction>.Step, _ mode: UndoHistory<UndoAction>.Mode) {
        if let last = undoNoticeId { status.dismiss(last) }
        let name = String(localized: step.name)
        let notice = Notice(
            title: String(localized: mode == .undoing ? .undoneAction(action: name) : .redoneAction(action: name)),
            message: subject(of: step) ?? "",
            symbol: mode == .undoing ? "arrow.uturn.backward" : "arrow.uturn.forward"
        )
        undoNoticeId = notice.id
        status.post(notice)
    }

    /// "#12 Title" when a step is about one issue.
    private func subject(of step: UndoHistory<UndoAction>.Step) -> String? {
        var issues = Set<String>()
        var item: Item?
        for case .changes(let mutations) in step.actions {
            for mutation in mutations {
                let remaps = status.idRemaps
                let mapped = mutation.remapping(remaps)
                if let contentId = mapped.contentId {
                    issues.insert(contentId)
                    item = item ?? issue(contentId: contentId)
                } else if let itemId = mapped.itemId {
                    issues.insert(itemId)
                    item = item ?? self.item(id: itemId)
                }
            }
        }
        guard issues.count == 1, let item else { return nil }
        return "\(item.displayNumber) \(item.title)"
    }

    // MARK: The menu commands

    /// Whether the commands are about the app's history right now: not while text has the keyboard, a dialog or the
    /// command palette is open, or a card is being dragged.
    private var historyIsInReach: Bool {
        guard signedIn, !textHasKeyboard, !isDragging else { return false }
        #if os(macOS)
        return overlay == nil
        #else
        return true
        #endif
    }

    var undoCommandTitle: String {
        guard historyIsInReach, let step = undoHistory.nextUndo else { return String(localized: .undo) }
        return String(localized: .undoAction(action: String(localized: step.name)))
    }

    var redoCommandTitle: String {
        guard historyIsInReach, let step = undoHistory.nextRedo else { return String(localized: .redo) }
        return String(localized: .redoAction(action: String(localized: step.name)))
    }

    var canUndoCommand: Bool { textHasKeyboard || (historyIsInReach && undoHistory.nextUndo != nil) }
    var canRedoCommand: Bool { textHasKeyboard || (historyIsInReach && undoHistory.nextRedo != nil) }

    func undoCommand() {
        if textIsInFront { textUndoManager?.undo() } else if historyIsInReach { undo() }
    }

    func redoCommand() {
        if textIsInFront { textUndoManager?.redo() } else if historyIsInReach { redo() }
    }

    #if os(macOS)
    /// Whether the keys belong to text being typed in, or to another window (Settings, a picker's dropdown, an alert),
    /// which keeps them to itself as text does.
    var keyboardIsWithText: Bool {
        let window = NSApp.keyWindow ?? mainWindow
        if let window, let mainWindow, window !== mainWindow { return true }
        return (window?.firstResponder as? NSTextView)?.isEditable == true
    }
    #endif

    /// Asked again when a command runs, so a key can never reach the app's history from inside text.
    private var textIsInFront: Bool {
        #if os(macOS)
        textHasKeyboard || keyboardIsWithText
        #else
        textHasKeyboard
        #endif
    }

    /// The undo of the text that has the keyboard, in whichever window it is.
    private var textUndoManager: UndoManager? {
        #if os(macOS)
        (NSApp.keyWindow ?? mainWindow)?.firstResponder?.undoManager
        #else
        UIResponder.keyboardOwner?.undoManager
        #endif
    }
}

/// Undo and Redo in the Edit menu, with ⌘Z and ⇧⌘Z, on the Mac and in the iPad's menu bar.
struct UndoCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(model.undoCommandTitle) { model.undoCommand() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndoCommand)
            Button(model.redoCommandTitle) { model.redoCommand() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedoCommand)
        }
    }
}

// MARK: - A board's columns

extension AppModel {
    /// Notes how to go back to the columns as they were: their order, names and colours. A column deleted with issues in
    /// it can't come back, since those issues have lost their status with it.
    func recordColumnsUndo(projectId: String, before: [FieldOption], after: [RemoteOption]) {
        let kept = Set(after.compactMap(\.id))
        let removed = before.filter { option in
            !kept.contains(option.id) && !after.contains { $0.id == nil && OptionMerge.sameName($0.name, option.name) }
        }
        guard removed.allSatisfy({ issueCount(projectId: projectId, statusId: $0.id) == 0 }) else { return }
        // A column that goes away comes back as a new one, by name: GitHub forgets the old one's id.
        let removedIds = Set(removed.map(\.id))
        let previous = before.map { option -> RemoteOption in
            var remote = option.remote
            if removedIds.contains(option.id) { remote.id = nil }
            return remote
        }
        let added = after.filter { new in new.id == nil && !before.contains { OptionMerge.sameName($0.name, new.name) } }.map(\.name)
        recordUndo(.restore { model in
            model.restoreColumns(projectId: projectId, to: previous, without: added)
        }, name: .actionChangeColumns)
    }

    /// Goes back to `previous`, leaving alone columns made since by anything but the change being taken back (`added`).
    /// When that would take away a column issues have moved into, nothing happens and the step is passed over.
    private func restoreColumns(projectId: String, to previous: [RemoteOption], without added: [String]) {
        let current = statusOptions(projectId: projectId)
        let isOurs = { (option: FieldOption) in added.contains { OptionMerge.sameName($0, option.name) } }
        guard current.filter(isOurs).allSatisfy({ issueCount(projectId: projectId, statusId: $0.id) == 0 }) else { return }
        let known = current.filter { option in
            !isOurs(option) && !previous.contains { $0.id == option.id || OptionMerge.sameName($0.name, option.name) }
        }
        saveColumns(projectId: projectId, previous + known.map(\.remote))
    }
}
