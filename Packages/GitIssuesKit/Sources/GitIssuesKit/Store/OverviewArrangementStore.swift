import Foundation
import Observation

/// How My Issues' overview is arranged (see `MineArrangement`). It lives in iCloud's key-value store, so the user's
/// Mac, iPhone and iPad show the same widgets in the same order, and is mirrored on the device for builds without
/// iCloud. The sample data keeps it in memory only.
@MainActor
@Observable
final class OverviewArrangementStore {
    /// The arrangement with when it last changed: iCloud keeps the last write, and a device that changed it while
    /// offline keeps its change when it is the newer one.
    struct Record: Codable, Equatable {
        var arrangement: MineArrangement
        var modified: Date
    }

    private(set) var record = Record(arrangement: MineArrangement(), modified: .distantPast)
    /// Told when another device's arrangement came in, so the overview's order for the keyboard follows.
    @ObservationIgnored var onChange: () -> Void = {}

    @ObservationIgnored private let cloud: NSUbiquitousKeyValueStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private static let key = "mine.arrangement"

    /// `persistent: false` keeps it in memory, for the sample data and tests.
    init(persistent: Bool) {
        cloud = persistent ? NSUbiquitousKeyValueStore.default : nil
        defaults = persistent ? .standard : nil
        guard persistent else { return }
        if let data = defaults?.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Record.self, from: data) {
            record = saved
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mergeFromCloud() }
        }
        cloud?.synchronize()
        mergeFromCloud()
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var arrangement: MineArrangement { record.arrangement }

    func set(_ arrangement: MineArrangement) {
        guard arrangement != record.arrangement else { return }
        record = Record(arrangement: arrangement, modified: Date())
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(record) else { return }
        cloud?.set(data, forKey: Self.key)
        defaults?.set(data, forKey: Self.key)
    }

    /// Takes what another device wrote when it is newer, and hands it this one's when this one is newer.
    private func mergeFromCloud() {
        guard let cloud else { return }
        guard let data = cloud.data(forKey: Self.key), let theirs = try? JSONDecoder().decode(Record.self, from: data) else {
            // Written here while iCloud wasn't reachable.
            if record.modified > .distantPast { save() }
            return
        }
        if record.modified >= theirs.modified {
            if record != theirs { save() }
        } else {
            record = theirs
            defaults?.set(data, forKey: Self.key)
            onChange()
        }
    }
}
