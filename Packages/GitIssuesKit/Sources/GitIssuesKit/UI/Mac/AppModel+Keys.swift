#if os(macOS)
import AppKit
import SwiftUI

/// Single-key shortcuts, Linear style. They act on the open issue, or else on the card or row under
/// the pointer or keyboard focus, and stay out of the way while typing.
extension AppModel {
    /// On the board: left and right jump to the neighbouring column, keeping the row where possible.
    private func stepColumn(_ delta: Int) {
        guard viewMode == .board, openItem == nil else { return }
        let filled = columns.filter { !$0.items.isEmpty }
        guard !filled.isEmpty else { return }
        let current = cursorId
        guard let columnIndex = filled.firstIndex(where: { column in column.items.contains { $0.id == current } }),
              let row = filled[columnIndex].items.firstIndex(where: { $0.id == current }) else {
            moveFocus(to: filled[0].items[0].id)
            return
        }
        let target = filled[min(max(columnIndex + delta, 0), filled.count - 1)]
        moveFocus(to: target.items[min(row, target.items.count - 1)].id)
    }

    private func stepWithinColumn(_ delta: Int) {
        let current = cursorId
        guard let column = columns.first(where: { column in column.items.contains { $0.id == current } }),
              let row = column.items.firstIndex(where: { $0.id == current }) else {
            step(delta)
            return
        }
        moveFocus(to: column.items[min(max(row + delta, 0), column.items.count - 1)].id)
    }

    /// How long after a dialog opens keystrokes are held for its text field.
    static let typeAheadWindow: TimeInterval = 0.5

    private func hold(_ event: NSEvent) {
        heldKeys.append(event)
        guard heldKeysTimer == nil else { return }
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                let fieldHasFocus = NSApp.keyWindow?.firstResponder is NSTextView
                let expired = self.overlayOpenedAt.map { Date().timeIntervalSince($0) >= Self.typeAheadWindow } ?? true
                guard fieldHasFocus || expired || self.overlay == nil else { return }
                timer.invalidate()
                self.heldKeysTimer = nil
                let events = self.heldKeys
                self.heldKeys = []
                // Sent again in order; now that the field has focus they go straight to it.
                for event in events { NSApp.sendEvent(event) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heldKeysTimer = timer
    }

    func installKeyMonitor() {
        guard keyMonitorToken == nil else { return }
        keyMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
    }

    /// Returns true when the key was used.
    private func handle(_ event: NSEvent) -> Bool {
        guard signedIn else { return false }
        // Alerts, the settings window and popovers handle their own keys.
        if let key = NSApp.keyWindow, let mainWindow, key !== mainWindow { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        let isEscape = event.keyCode == 53

        if isDragging {
            if isEscape {
                dragCancelToken += 1
                return true
            }
            return false
        }
        // Escape always closes the palette or dialog, whatever has focus inside it. A popover of the dialog
        // (a picker) is a window of its own and closes itself first.
        if isEscape, overlay != nil, NSApp.keyWindow == nil || NSApp.keyWindow === mainWindow {
            overlay = nil
            return true
        }
        // Overlays and text fields handle their own keys. A dialog's text field only takes focus once the
        // dialog is on screen, so typing that starts right away is held and handed over when it can land.
        if overlay != nil {
            let fieldHasFocus = NSApp.keyWindow?.firstResponder is NSTextView
            let justOpened = overlayOpenedAt.map { Date().timeIntervalSince($0) < Self.typeAheadWindow } ?? false
            if !heldKeys.isEmpty || (!fieldHasFocus && justOpened && modifiers.isEmpty && !isEscape) {
                hold(event)
                return true
            }
            return false
        }
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView { return false }
        // ⌘⌫ deletes the issue in focus, as in Linear. Inside a text field it keeps deleting text.
        if modifiers == .command, event.keyCode == 51, let item = actionItem, targets(for: item).count == 1 {
            requestDelete(item)
            return true
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if scope == .inbox, let handled = handleInboxKey(event, key: key, modifiers: modifiers) {
            return handled
        }
        // ⌘A picks every issue on screen.
        if modifiers == .command, key == "a", openItem == nil, !orderedItems.isEmpty {
            selectAll()
            return true
        }
        // ⌥↑ and ⌥↓ (or ⌥K and ⌥J) move the issue up or down its column, or its section of the list. The
        // keyboard focus goes with it, so pressing again keeps moving the same issue.
        if modifiers == .option, openItem == nil, currentProjectId != nil,
           let delta = [125: 1, 126: -1][Int(event.keyCode)] ?? ["j": 1, "k": -1][key] {
            if let id = cursorId, let item = scopedItems.first(where: { $0.id == id }), move(item, by: delta) {
                moveFocus(to: item.id)
            }
            return true
        }
        guard modifiers.isEmpty else { return false }

        // Escape steps back one layer at a time: the peek, then the open issue, then the selection.
        if isEscape {
            if peekItemId != nil {
                togglePeek()
                return true
            }
            if openItem != nil {
                leaveIssue()
                return true
            }
            if !selectedIds.isEmpty {
                clearSelection()
                return true
            }
            return false
        }

        if openItem == nil {
            // Space peeks at the issue under the pointer or focus, and closes the peek again.
            if event.keyCode == 49 {
                togglePeek()
                return true
            }
            // X picks the issue, or puts it back.
            if key == "x", let item = targetItem {
                toggleSelection(item)
                return true
            }
            // Shift with the arrows or J/K picks a run of issues while moving.
            let shift = event.modifierFlags.contains(.shift)
            let delta = [125: 1, 126: -1][Int(event.keyCode)] ?? ["j": 1, "k": -1][key]
            if shift, let delta {
                if selectedIds.isEmpty, let start = targetItem { toggleSelection(start) }
                if viewMode == .board, currentProjectId != nil { stepWithinColumn(delta) } else { step(delta) }
                if let id = focusedItemId, let item = scopedItems.first(where: { $0.id == id }) { extendSelection(to: item) }
                return true
            }
        }

        // Two-key "go to" sequences: G then B, L, M or P.
        if let started = pendingGoTo, Date().timeIntervalSince(started) < 1.2 {
            pendingGoTo = nil
            switch key {
            case "b":
                // From the Inbox or My Issues, back to the project used last.
                if currentProjectId == nil { selectLastProject() }
                if currentProjectId != nil {
                    closeDetail()
                    withAnimation(Theme.spring) { viewMode = .board }
                }
                return true
            case "l":
                if scope == .inbox { selectLastProject() }
                closeDetail()
                withAnimation(Theme.spring) { viewMode = .list }
                return true
            case "m":
                select(.myIssues)
                return true
            case "i":
                select(.inbox)
                return true
            case "p":
                overlay = .palette(.projects)
                return true
            default:
                break
            }
        }

        switch event.keyCode {
        case 125: // down
            if viewMode == .board, openItem == nil, currentProjectId != nil { stepWithinColumn(1) } else { step(1) }
            return true
        case 126: // up
            if viewMode == .board, openItem == nil, currentProjectId != nil { stepWithinColumn(-1) } else { step(-1) }
            return true
        case 123: // left
            stepColumn(-1)
            return viewMode == .board && openItem == nil
        case 124: // right
            stepColumn(1)
            return viewMode == .board && openItem == nil
        case 36: // return
            if openItem == nil, let item = peekItem ?? targetItem {
                open(item)
                return true
            }
            return false
        default:
            break
        }

        switch key {
        case "g":
            pendingGoTo = Date()
            return true
        case "c":
            guard currentProjectId != nil || !projects.isEmpty else { return false }
            overlay = .newIssue(statusId: nil, parentItemId: nil)
            return true
        case "/":
            overlay = .palette(.root)
            return true
        case "j":
            step(1)
            return true
        case "k":
            step(-1)
            return true
        default:
            break
        }

        // With issues picked, these act on all of them.
        guard let item = actionItem else { return false }
        switch key {
        case "s":
            overlay = .palette(.status(itemId: item.id))
        case "p":
            guard project(of: item)?.priorityFieldId != nil else { return false }
            overlay = .palette(.priority(itemId: item.id))
        case "a":
            guard item.kind != .draft else { return false }
            overlay = .palette(.assignees(itemId: item.id))
        case "l":
            guard item.kind != .draft else { return false }
            overlay = .palette(.labels(itemId: item.id))
        case "i":
            guard item.kind != .draft, viewer != nil else { return false }
            toggleAssignMe(targets(for: item))
        case "d":
            guard targets(for: item).contains(where: canHaveDueDate) else { return false }
            overlay = .palette(.dueDate(itemId: item.id))
        default:
            return false
        }
        return true
    }

    /// The Inbox's own keys, as in Linear: J and K move and show the issue, U reads, E or ⌫ archives, H snoozes,
    /// ⇧S unsubscribes, ⌥U reads everything and ⇧⌫ archives everything read. Returns nil for keys it leaves to the
    /// rest, such as S, P, A, L and I, which act on the selected entry's issue as anywhere else.
    private func handleInboxKey(_ event: NSEvent, key: String, modifiers: NSEvent.ModifierFlags) -> Bool? {
        let shift = event.modifierFlags.contains(.shift)
        if modifiers == .command, key == "z", inboxUndo != nil {
            undoInbox()
            return true
        }
        // With the issue open full size, J and K go on to the next notification's issue.
        if let openItem {
            guard modifiers.isEmpty, !shift, key == "j" || key == "k" else { return nil }
            stepInboxOpen(key == "j" ? 1 : -1, from: openItem)
            return true
        }
        if modifiers == .command, key == "a" {
            inboxPicked = Set(visibleInbox.map(\.id))
            return true
        }
        if modifiers == .option, key == "u" {
            markAllRead()
            return true
        }
        guard modifiers.isEmpty else { return nil }
        // The key after G belongs to the "go to" sequence.
        if let started = pendingGoTo, Date().timeIntervalSince(started) < 1.2 { return nil }
        if event.keyCode == 53 {
            guard !inboxPicked.isEmpty else { return nil }
            inboxPicked = []
            return true
        }
        let targets = inboxPicked.isEmpty
            ? inboxSelected.map { [$0] } ?? []
            : visibleInbox.filter { inboxPicked.contains($0.id) }
        let delta = [125: 1, 126: -1][Int(event.keyCode)] ?? ["j": 1, "k": -1][key]
        if let delta {
            if shift, let current = inboxSelected ?? visibleInbox.first {
                // Shift with the arrows or J/K picks a run, as in the list.
                if inboxPicked.isEmpty { inboxPicked = [current.id] }
                stepInbox(delta)
                if let reached = inboxSelected { extendInboxPick(to: reached) }
            } else {
                stepInbox(delta)
            }
            return true
        }
        switch event.keyCode {
        case 36: // return
            if let entry = inboxSelected, let item = inboxItem(for: entry), !item.isDetached { open(item) }
            return true
        case 51: // delete
            if shift { archiveAllRead() } else { archive(targets) }
            return true
        case 49: // space: the issue is beside the list already
            return true
        default:
            break
        }
        switch key {
        case "u":
            toggleRead(targets)
        case "e":
            archive(targets)
        case "h":
            guard !targets.isEmpty else { return true }
            inboxSnoozeRequest = InboxSnoozeRequest(token: inboxSnoozeRequest.token + 1, pickDate: false)
        case "s" where shift:
            unsubscribe(targets)
        case "x":
            if let entry = inboxSelected { toggleInboxPick(entry) }
        default:
            return nil
        }
        return true
    }
}
#endif
