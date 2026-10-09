import Foundation
import Observation

/// What the Inbox keeps that GitHub has no place for: entries snoozed until later, entries marked unread again,
/// whether the entries the app makes itself (issues that are due, assignments made with your own account) were read
/// or archived, and when the app assigned you to an issue, which GitHub can't tell from an assignment made with `gh`.
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
        /// Read, for an entry GitHub doesn't know: when.
        var read: Date?
        /// Archived, for an entry GitHub doesn't know: when.
        var archived: Date?
        /// For an issue rather than an entry: when the app assigned you to it, on any of your devices.
        var assignedHere: [Date]?
        var modified: Date

        var isEmpty: Bool { snooze == nil && unreadFor == nil && read == nil && archived == nil && assignedHere == nil }

        /// Equal apart from when it changed.
        func sameContent(as other: Record) -> Bool {
            snooze == other.snooze && unreadFor == other.unreadFor && read == other.read && archived == other.archived
                && assignedHere == other.assignedHere
        }
    }

    private(set) var records: [String: Record] = [:]

    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private static let prefix = "inbox."
    private static let mirrorKey = "personalStore"
    /// Records left alone this long are dropped: iCloud's store holds at most 1024 keys.
    private static let lifetime: TimeInterval = 30 * 86_400
    /// Records of assignments the app made are needed only until their assignment has come back from GitHub.
    private static let assignedHereLifetime: TimeInterval = InboxEntry.assignedHereAfter
    /// Issues have a record of their own, apart from the entries about them.
    private static let issuePrefix = "issue:"

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

    /// Whether an entry the app makes itself has been read.
    public func isRead(_ entryId: String) -> Bool {
        records[entryId]?.read != nil
    }

    /// Whether an entry the app makes itself has been archived.
    public func isArchived(_ entryId: String) -> Bool {
        records[entryId]?.archived != nil
    }

    /// When the app assigned you to the issue, on this device or another of yours, within the last week.
    public func assignedHere(_ contentId: String) -> [Date] {
        records[Self.issuePrefix + contentId]?.assignedHere ?? []
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

    public func setRead(_ entryId: String, _ read: Bool) {
        update(entryId) { $0.read = read ? $0.read ?? Date() : nil }
    }

    public func setArchived(_ entryId: String, _ archived: Bool) {
        update(entryId) { $0.archived = archived ? $0.archived ?? Date() : nil }
    }

    /// The app assigned you to the issue at `date`. GitHub records it as an assignment by your account, as it does one
    /// made with `gh`; this tells the Inbox on all your devices that it is no news. Noting the same moment twice
    /// changes nothing.
    public func noteAssignedHere(_ contentId: String, at date: Date) {
        let cutoff = Date().addingTimeInterval(-Self.assignedHereLifetime)
        guard date > cutoff else { return }
        update(Self.issuePrefix + contentId) { record in
            var dates = (record.assignedHere ?? []).filter { $0 > cutoff }
            if !dates.contains(date) { dates.append(date) }
            record.assignedHere = Array(dates.sorted().suffix(10))
        }
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
        guard !record.sameContent(as: before) else { return }
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
        let assignedCutoff = Date().addingTimeInterval(-Self.assignedHereLifetime)
        for (key, record) in records where key.hasPrefix(Self.issuePrefix) && record.modified < assignedCutoff {
            remove(key)
        }
    }
}
