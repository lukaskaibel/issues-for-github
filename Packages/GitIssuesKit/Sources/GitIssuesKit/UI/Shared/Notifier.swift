import Observation
import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Reminders of due issues. Each device schedules them itself from the issues it has synced, so no server is
/// involved: on the day an open issue assigned to you is due, at the time set in Settings, and once more the
/// morning after if it is still open. Their buttons start the issue, mark it done or move it to tomorrow.
@MainActor
@Observable
final class Notifier {
    static let shared = Notifier()

    /// The category of due-date notifications and its buttons.
    static let dueCategory = "DUE"
    enum Action {
        static let start = "start"
        static let done = "done"
        static let tomorrow = "tomorrow"
    }

    /// What a notification carries to find its issue again. An inbox entry may add its own id later.
    enum Key {
        static let itemId = "itemId"
        static let contentId = "contentId"
        static let projectId = "projectId"
    }

    private static let prefixes = ["due:", "overdue:"]
    /// iOS keeps at most 64 scheduled notifications per app; the nearest ones are scheduled.
    private static let limit = 60

    // MARK: Settings, kept on this device

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "reminders.enabled")
            scheduleSoon(delay: .zero)
            if enabled { requestPermissionIfNeeded(force: true) }
        }
    }

    /// Minutes after midnight; 9:00 at first.
    var minutes: Int {
        didSet {
            UserDefaults.standard.set(minutes, forKey: "reminders.minutes")
            scheduleSoon(delay: .zero)
        }
    }

    var remindsWhenOverdue: Bool {
        didSet {
            UserDefaults.standard.set(remindsWhenOverdue, forKey: "reminders.overdue")
            scheduleSoon(delay: .zero)
        }
    }

    /// Whether the system lets the app show notifications, for Settings.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var scheduled: [String: String]?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let delegate = NotificationDelegate()
    @ObservationIgnored private var dayObserver: NSObjectProtocol?

    private init() {
        let defaults = UserDefaults.standard
        func has(_ key: String) -> Bool { defaults.object(forKey: key) != nil }
        enabled = has("reminders.enabled") ? defaults.bool(forKey: "reminders.enabled") : true
        minutes = has("reminders.minutes") ? min(max(defaults.integer(forKey: "reminders.minutes"), 0), 24 * 60 - 1) : 9 * 60
        remindsWhenOverdue = has("reminders.overdue") ? defaults.bool(forKey: "reminders.overdue") : true
    }

    /// Hooks up the notification centre. Called as the app launches, before a tapped notification is delivered.
    func install() {
        let center = UNUserNotificationCenter.current()
        guard center.delegate !== delegate else { return }
        center.delegate = delegate
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.dueCategory,
                actions: [
                    UNNotificationAction(identifier: Action.start, title: "Start", options: [], icon: UNNotificationActionIcon(systemImageName: "play.circle")),
                    UNNotificationAction(identifier: Action.done, title: "Mark as Done", options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark.circle")),
                    UNNotificationAction(identifier: Action.tomorrow, title: "Move to Tomorrow", options: [], icon: UNNotificationActionIcon(systemImageName: "calendar")),
                ],
                intentIdentifiers: []
            ),
        ])
        refreshAuthorization()
        // "Tomorrow" on a card becomes "Today" at midnight.
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model?.rebuild()
                self?.scheduleSoon(delay: .zero)
            }
        }
    }

    func attach(_ model: AppModel) {
        self.model = model
        install()
        scheduleSoon()
    }

    // MARK: Permission

    func refreshAuthorization() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if authorization != settings.authorizationStatus { authorization = settings.authorizationStatus }
        }
    }

    /// Asks once, when there is first something to remind of: a due date was set, or an issue with one was
    /// assigned to you. The sample data doesn't ask by itself (Settings has a button), so trying the app
    /// never ends in a system prompt.
    func requestPermissionIfNeeded(force: Bool = false) {
        guard enabled, let model, force || !model.isDemo, model.signedIn else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            refreshAuthorization()
            scheduled = nil
            scheduleSoon(delay: .zero)
        }
    }

    // MARK: Scheduling

    /// Works out the notifications again shortly after the issues changed; several changes in a row cost one pass.
    func scheduleSoon(delay: Duration = .seconds(1)) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await update()
        }
    }

    /// Brings the scheduled notifications in line with the issues, touching only what changed.
    func update() async {
        guard let model else { return }
        let wanted = enabled && model.signedIn ? requests(for: model) : []
        let signature = Dictionary(wanted.map { ($0.identifier, Self.fingerprint($0)) }, uniquingKeysWith: { first, _ in first })
        if signature.isEmpty == false, authorization == .notDetermined {
            requestPermissionIfNeeded()
        }
        let center = UNUserNotificationCenter.current()
        await clearDelivered(keeping: Set(wanted.map(\.identifier)), model: model)
        guard signature != scheduled else { return }
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { id in Self.prefixes.contains { id.hasPrefix($0) } }
        let stale = existing.filter { signature[$0] == nil }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        if Self.allowed(settings.authorizationStatus) {
            for request in wanted where scheduled?[request.identifier] != signature[request.identifier] {
                try? await center.add(request)
            }
            scheduled = signature
        } else {
            scheduled = nil
        }
    }

    private func requests(for model: AppModel) -> [UNNotificationRequest] {
        guard let viewer = model.viewer else { return [] }
        let now = Date()
        let calendar = CalendarDay.calendar
        var result: [(date: Date, request: UNNotificationRequest)] = []
        let closedProjects = Set(model.projects.filter(\.closed).map(\.id))
        for item in model.allItems {
            guard let day = item.due, let projectId = item.projectId, !closedProjects.contains(projectId),
                  item.assignees.contains(where: { $0.id == viewer.id }), !model.isDone(item) else { continue }
            let project = model.project(of: item)?.title
            let key = item.contentId ?? item.id
            var occasions = [("due", day, "Due today")]
            if remindsWhenOverdue {
                occasions.append(("overdue", day.adding(days: 1, calendar: calendar), "Overdue since yesterday"))
            }
            for (kind, fireDay, title) in occasions {
                var parts = fireDay.components
                parts.hour = minutes / 60
                parts.minute = minutes % 60
                guard let date = calendar.date(from: parts), date > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = project.map { "\(title) · \($0)" } ?? title
                content.body = "\(item.displayNumber) \(item.title)"
                content.sound = .default
                content.categoryIdentifier = Self.dueCategory
                content.threadIdentifier = projectId
                content.userInfo = [Key.itemId: item.id, Key.contentId: item.contentId ?? "", Key.projectId: projectId]
                // Without a time zone the time is local wherever the device is: 9:00 stays 9:00 when travelling.
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                let request = UNNotificationRequest(identifier: "\(kind):\(key):\(day.string)", content: content, trigger: trigger)
                result.append((date, request))
            }
        }
        return result.sorted { $0.date < $1.date }.prefix(Self.limit).map(\.request)
    }

    static func allowed(_ status: UNAuthorizationStatus) -> Bool {
        #if os(iOS)
        if status == .ephemeral { return true }
        #endif
        return status == .authorized || status == .provisional
    }

    private static func fingerprint(_ request: UNNotificationRequest) -> String {
        let trigger = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
        return [
            request.content.title, request.content.body,
            "\(trigger?.hour ?? 0):\(trigger?.minute ?? 0)",
            request.content.userInfo[Key.itemId] as? String ?? "",
        ].joined(separator: "|")
    }

    /// Takes delivered notifications away once their issue is done, moved to another day or no longer yours,
    /// so Notification Center doesn't keep reminders that no longer hold.
    private func clearDelivered(keeping wanted: Set<String>, model: AppModel) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        guard !delivered.isEmpty, let viewer = model.viewer else { return }
        var live = Set<String>()
        for item in model.allItems {
            guard let day = item.due, item.assignees.contains(where: { $0.id == viewer.id }), !model.isDone(item) else { continue }
            live.insert("\(item.contentId ?? item.id):\(day.string)")
        }
        let stale = delivered.filter { id in
            guard let prefix = Self.prefixes.first(where: { id.hasPrefix($0) }) else { return false }
            return !wanted.contains(id) && !live.contains(String(id.dropFirst(prefix.count)))
        }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }

    /// Takes away the delivered notifications of one issue, after acting on it from one of them.
    func clearDelivered(for item: Item) {
        let key = item.contentId ?? item.id
        Task {
            let center = UNUserNotificationCenter.current()
            let ids = await center.deliveredNotifications()
                .map(\.request.identifier)
                .filter { id in Self.prefixes.contains { id.hasPrefix("\($0)\(key):") } }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    // MARK: Answering

    func handle(action: String, userInfo: [String: String]) async {
        let model = model ?? AppModel.shared
        let itemId = userInfo[Key.itemId]
        let contentId = userInfo[Key.contentId].flatMap { $0.isEmpty ? nil : $0 }
        func find() -> Item? {
            contentId.flatMap { model.item(contentId: $0) } ?? itemId.flatMap { model.item(id: $0) }
        }
        var item = find()
        if item == nil {
            // Not synced on this device yet: fetch, then look again.
            await model.syncAndWait()
            item = find()
        }
        guard let item else { return }
        switch action {
        case Action.start:
            if let started = model.statusOptions(projectId: item.projectId).first(where: { $0.statusCategory == .started }) {
                model.setStatus(item, to: started)
            }
        case Action.done:
            if !model.isDone(item) { model.toggleDone(item) }
        case Action.tomorrow:
            model.setDueDate(of: [item], to: CalendarDay.today().adding(days: 1))
        case UNNotificationDefaultActionIdentifier:
            model.reveal(item)
            return
        default:
            return
        }
        clearDelivered(for: item)
        // Sent before the system suspends the app again; a few seconds are granted for that.
        await model.sendQueuedChanges()
    }
}

/// Receives notifications for `Notifier`. A separate object, since the notification centre wants an NSObject.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let keys = [Notifier.Key.itemId, Notifier.Key.contentId, Notifier.Key.projectId]
        let userInfo = Dictionary(uniqueKeysWithValues: keys.compactMap { key in (info[key] as? String).map { (key, $0) } })
        await Notifier.shared.handle(action: action, userInfo: userInfo)
    }
}

/// Hooks up notifications as the app launches, before a notification that launched it is handed over.
#if os(macOS)
public final class GitIssuesAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Notifier.shared.install() }
    }
}
#else
public final class GitIssuesAppDelegate: NSObject, UIApplicationDelegate {
    public func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { Notifier.shared.install() }
        return true
    }
}
#endif
