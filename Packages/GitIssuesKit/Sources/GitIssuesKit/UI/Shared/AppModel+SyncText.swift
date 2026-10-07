import SwiftUI

extension AppModel {
    /// One line on the state of syncing, e.g. "Synced 2 min ago" or "Offline · 3 queued".
    func syncLine(at now: Date = Date()) -> String {
        let pending = pendingCount
        if isDemo, status.phase != .syncing {
            #if DEBUG
            // App Store screenshots show the sample data the way a real account looks.
            if UserDefaults.standard.bool(forKey: "screenshotMode") { return String(localized: .syncedJustNow) }
            #endif
            return pending > 0 ? String(localized: .changesQueued(count: pending)) : String(localized: .sampleDataStatus)
        }
        switch status.phase {
        case .syncing:
            return pending > 0 ? String(localized: .syncingChanges(count: pending)) : String(localized: .syncing)
        case .offline:
            return pending > 0 ? String(localized: .offlineQueued(count: pending)) : String(localized: .offline)
        case .failed:
            return String(localized: .syncProblem)
        case .unauthorized:
            return String(localized: .signedOut)
        case .idle:
            if pending > 0 { return String(localized: .changesQueued(count: pending)) }
            guard let date = status.lastSyncedAt else { return String(localized: .notSyncedYet) }
            let seconds = now.timeIntervalSince(date)
            if seconds < 45 { return String(localized: .syncedJustNow) }
            if seconds < 3600 { return String(localized: .syncedMinutesAgo(minutes: Int(seconds / 60) + 1)) }
            return String(localized: .syncedAtTime(time: date.formatted(date: .omitted, time: .shortened)))
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
        (try? db.reader.read { try entry.mutation.summary($0) }) ?? ("", String(localized: .changeWithoutSummary))
    }
}
