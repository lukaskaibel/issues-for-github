import Foundation
import Observation

/// What the Inbox keeps that GitHub has no place for: entries snoozed until later, and entries marked unread again.
/// It lives in iCloud's key-value store, so the user's Mac, iPhone and iPad agree, and is mirrored on the device for
/// builds without iCloud (development builds without a team). The sample data keeps it in memory only.
@MainActor
@Observable
public final class PersonalStore {
    public struct Snooze: Codable, Equatable, Sendable {
        public var until: Date
        /// The thread's last activity when it was snoozed. Newer activity brings it back early.
        public var threadUpdatedAt: Date
    }

    /// One record per Inbox entry, with when it last changed. iCloud keeps the last write per key, so one key per
    /// entry lets two devices change different entries without overwriting each other. Clearing an entry leaves
    /// an empty record behind for a while, so a device that was offline doesn't bring the old one back.
    struct Record: Codable, Equatable, Sendable {
        var snooze: Snooze?
        /// Marked unread: the thread's last activity at the time.
        var unreadFor: Date?
        var modified: Date

        var isEmpty: Bool { snooze == nil && unreadFor == nil }
    }

    private(set) var records: [String: Record] = [:]

    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private static let prefix = "inbox."
    private static let mirrorKey = "personalStore"
    /// Records left alone this long are dropped: iCloud's store holds at most 1024 keys.
    private static let lifetime: TimeInterval = 30 * 86_400

    /// `persistent: false` keeps everything in memory, for the sample data and tests.
    public init(persistent: Bool) {
        cloud = persistent ? NSUbiquitousKeyValueStore.default : nil
        defaults = persistent ? .standard : nil
        guard persistent else { return }
        for (key, data) in defaults?.dictionary(forKey: Self.mirrorKey) as? [String: Data] ?? [:] {
            if let record = try? JSONDecoder().decode(Record.self, from: data) { records[key] = record }
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mergeFromCloud() }
        }
        cloud?.synchronize()
        mergeFromCloud()
        prune()
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Reading

    public func snooze(_ threadId: String) -> Snooze? {
        records[threadId]?.snooze
    }

    /// The thread's last activity when the entry was marked unread, if it was.
    public func markedUnread(_ threadId: String) -> Date? {
        records[threadId]?.unreadFor
    }

    /// The earliest moment a snoozed entry comes back, to look again then.
    public var nextWake: Date? {
        records.values.compactMap { $0.snooze?.until }.filter { $0 > Date() }.min()
    }

    // MARK: Writing

    public func setSnooze(_ threadId: String, _ snooze: Snooze?) {
        update(threadId) { $0.snooze = snooze }
    }

    public func setMarkedUnread(_ threadId: String, _ updatedAt: Date?) {
        update(threadId) { $0.unreadFor = updatedAt }
    }

    /// Forgets everything about the entry: opened, archived or read again.
    public func clear(_ threadId: String) {
        guard let record = records[threadId], !record.isEmpty else { return }
        update(threadId) { $0 = Record(modified: $0.modified) }
    }

    /// Puts a record back as it was before a change, for undo.
    func restore(_ threadId: String, _ record: Record?) {
        var restored = record ?? Record(modified: Date())
        restored.modified = Date()
        records[threadId] = restored
        save(threadId, restored)
    }

    private func update(_ threadId: String, _ change: (inout Record) -> Void) {
        var record = records[threadId] ?? Record(modified: Date())
        let before = record
        change(&record)
        guard record.snooze != before.snooze || record.unreadFor != before.unreadFor else { return }
        record.modified = Date()
        records[threadId] = record
        save(threadId, record)
    }

    // MARK: Storage

    private func save(_ threadId: String, _ record: Record) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        cloud?.set(data, forKey: Self.prefix + threadId)
        guard let defaults else { return }
        var mirror = defaults.dictionary(forKey: Self.mirrorKey) as? [String: Data] ?? [:]
        mirror[threadId] = data
        defaults.set(mirror, forKey: Self.mirrorKey)
    }

    private func remove(_ threadId: String) {
        records[threadId] = nil
        cloud?.removeObject(forKey: Self.prefix + threadId)
        guard let defaults else { return }
        var mirror = defaults.dictionary(forKey: Self.mirrorKey) as? [String: Data] ?? [:]
        mirror[threadId] = nil
        defaults.set(mirror, forKey: Self.mirrorKey)
    }

    /// Takes what other devices wrote when it is newer, and hands them what this one has that is newer.
    private func mergeFromCloud() {
        guard let cloud else { return }
        var seen = Set<String>()
        for (key, value) in cloud.dictionaryRepresentation where key.hasPrefix(Self.prefix) {
            let threadId = String(key.dropFirst(Self.prefix.count))
            seen.insert(threadId)
            guard let data = value as? Data, let theirs = try? JSONDecoder().decode(Record.self, from: data) else { continue }
            if let mine = records[threadId], mine.modified >= theirs.modified {
                if mine != theirs { save(threadId, mine) }
            } else {
                records[threadId] = theirs
                save(threadId, theirs)
            }
        }
        // Written here while iCloud wasn't reachable.
        for (threadId, record) in records where !seen.contains(threadId) {
            save(threadId, record)
        }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.lifetime)
        for (threadId, record) in records where record.modified < cutoff {
            let expired = record.snooze.map { $0.until < Date() } ?? true
            if record.isEmpty || expired { remove(threadId) }
        }
    }
}
