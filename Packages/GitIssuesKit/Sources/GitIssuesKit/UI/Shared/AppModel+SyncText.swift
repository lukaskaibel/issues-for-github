import SwiftUI

extension AppModel {
    /// One line on the state of syncing, e.g. "Synced 2 min ago" or "Offline · 3 queued".
    func syncLine(at now: Date = Date()) -> String {
        let pending = pendingCount
        let changes = "\(pending) change\(pending == 1 ? "" : "s")"
        if isDemo, status.phase != .syncing {
            #if DEBUG
            // App Store screenshots show the sample data the way a real account looks.
            if UserDefaults.standard.bool(forKey: "screenshotMode") { return "Synced just now" }
            #endif
            return pending > 0 ? "\(changes) queued" : "Sample data"
        }
        switch status.phase {
        case .syncing:
            return pending > 0 ? "Syncing \(changes)…" : "Syncing…"
        case .offline:
            return pending > 0 ? "Offline · \(pending) queued" : "Offline"
        case .failed:
            return "Sync problem"
        case .unauthorized:
            return "Signed out"
        case .idle:
            if pending > 0 { return "\(changes) queued" }
            guard let date = status.lastSyncedAt else { return "Not synced yet" }
            let seconds = now.timeIntervalSince(date)
            if seconds < 45 { return "Synced just now" }
            if seconds < 3600 { return "Synced \(Int(seconds / 60) + 1) min ago" }
            return "Synced \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    /// The colour of the dot next to that line.
    var syncDotColor: Color {
        switch status.phase {
        case .offline, .failed, .unauthorized: Theme.warning
        case .syncing, .idle: pendingCount > 0 ? Theme.accent : Theme.positive
        }
    }

    func summary(of entry: OutboxEntry) -> (number: String, text: String) {
        (try? db.reader.read { try entry.mutation.summary($0) }) ?? ("", "Change")
    }
}
