import SwiftUI

/// Back and forward through the places visited, the way a browser does it.
extension AppModel {
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }

    /// Notes the current place after the user went somewhere. Anything ahead in the history is dropped.
    /// `replacing` swaps out the current place instead, for moving to the next issue with J or K.
    func recordNavigation(replacing: Bool = false) {
        guard !isRestoringLocation, scope != nil else { return }
        let current = Location(scope: scope, viewMode: viewMode, itemId: openItemId)
        if historyIndex >= 0, history.indices.contains(historyIndex), history[historyIndex] == current { return }
        if replacing, history.indices.contains(historyIndex), history[historyIndex].itemId != nil {
            history[historyIndex] = current
            history.removeSubrange((historyIndex + 1)...)
            return
        }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(current)
        if history.count > 200 { history.removeFirst(history.count - 200) }
        historyIndex = history.count - 1
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        restore(history[historyIndex])
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        restore(history[historyIndex])
    }

    private func restore(_ location: Location) {
        isRestoringLocation = true
        defer { isRestoringLocation = false }
        overlay = nil
        if let target = location.scope, target != scope {
            select(target)
        }
        if viewMode != location.viewMode {
            withAnimation(Theme.spring) { viewMode = location.viewMode }
        }
        if let id = location.itemId, let item = allItems.first(where: { $0.id == id }) {
            if openItemId != id { open(item) }
        } else {
            closeDetail()
        }
    }
}
