import StoreKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Asks you to rate Issues on the App Store, with the system's own prompt. It asks once you have used Issues on three
/// days, signed in to GitHub, and only as you finish an issue: closed as completed, or moved into a done column. Never as
/// the app opens, never on sample data, and at most once a version and two months apart. The system shows its prompt at
/// most three times a year, never in TestFlight, and not at all once it is turned off in the App Store's settings.
/// Rate Issues on the App Store, in the app menu on the Mac and in the account sheet on iPhone and iPad, is always there.
///
/// Not in Debug builds, where the system shows its prompt every time: `-debugAsksForReview YES` asks at every such
/// moment, in any build, sample data too.
@MainActor
final class AppReview {
    static let shared = AppReview()

    /// The app's page in the App Store, open to write a review: in the App Store app on the Mac, iPhone and iPad.
    static let writeReviewURL: URL = {
        #if os(macOS)
        URL(string: "macappstore://apps.apple.com/app/id6819589759?action=write-review")!
        #else
        URL(string: "https://apps.apple.com/app/id6819589759?action=write-review")!
        #endif
    }()

    private let defaults: UserDefaults
    private let version: String
    private let mayAsk: Bool
    private(set) var record: ReviewRecord
    private var isStarted = false
    private var isAsking = false
    /// What you did shows first: the issue ticked, the card in its column.
    var delay: TimeInterval = 1
    /// Shows the system's prompt in the window in front, and says whether there was one; tests look instead.
    var prompt: () -> Bool = AppReview.showPrompt

    init(defaults: UserDefaults = .standard, version: String? = nil, mayAsk: Bool? = nil) {
        self.defaults = defaults
        self.version = version ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        #if DEBUG
        self.mayAsk = mayAsk ?? false
        #else
        self.mayAsk = mayAsk ?? true
        #endif
        record = ReviewRecord(daysUsed: defaults.stringArray(forKey: Key.daysUsed) ?? [],
                              askedVersion: defaults.string(forKey: Key.askedVersion),
                              askedDate: defaults.object(forKey: Key.askedDate) as? Date)
    }

    private enum Key {
        static let daysUsed = "review.daysUsed"
        static let askedVersion = "review.askedVersion"
        static let askedDate = "review.askedDate"
        static let always = "debugAsksForReview"
    }

    /// Counts the days Issues is used on: today, and each day it comes to the front. Signed in, not on sample data.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        used()
        #if os(macOS)
        let active = NSApplication.didBecomeActiveNotification
        #else
        let active = UIApplication.didBecomeActiveNotification
        #endif
        NotificationCenter.default.addObserver(forName: active, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.used() }
        }
    }

    /// Issues is in use on this day.
    func used(on date: Date = Date()) {
        guard record.use(on: date) else { return }
        defaults.set(record.daysUsed, forKey: Key.daysUsed)
    }

    /// You finished something, at a moment the prompt doesn't get in the way: it shows if the time for it has come.
    /// `stillFits`: asked again a moment later, as you may have gone on to something new meanwhile.
    func finishedSomething(at date: Date = Date(), stillFits: @escaping @MainActor () -> Bool = { true }) {
        let always = defaults.bool(forKey: Key.always)
        guard always || (isStarted && mayAsk && record.isDue(version: version, at: date)), !isAsking else { return }
        isAsking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            isAsking = false
            guard stillFits(), prompt(), !always else { return }
            record.asked(version: version, at: date)
            defaults.set(record.askedVersion, forKey: Key.askedVersion)
            defaults.set(record.askedDate, forKey: Key.askedDate)
        }
    }

    private static func showPrompt() -> Bool {
        #if os(macOS)
        // Not while another app is in front: a notification's Done, say.
        guard NSApp.isActive, let controller = (NSApp.keyWindow ?? NSApp.mainWindow)?.contentViewController else { return false }
        AppStore.requestReview(in: controller)
        #else
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.activationState == .foregroundActive }
        guard let scene = scenes.first(where: { $0.keyWindow != nil }) ?? scenes.first else { return false }
        AppStore.requestReview(in: scene)
        #endif
        return true
    }
}

/// What asking for a rating goes by: the days the app was used on, and when it last asked.
struct ReviewRecord: Equatable {
    /// The days the app came to the front on, the latest last, as year-month-day: only the last few.
    var daysUsed: [String] = []
    /// The version that asked last, and when.
    var askedVersion: String?
    var askedDate: Date?

    /// Days used before the first time it asks: time to know the app, and you came back to it.
    static let daysBeforeAsking = 3
    /// Days between one time and the next, each in another version: three times a year, as many as the system shows.
    static let daysBetweenAsking = 60

    /// The app is in use on the day of `date`. True when that day is new to the record.
    mutating func use(on date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        guard !daysUsed.contains(day) else { return false }
        daysUsed = Array((daysUsed + [day]).suffix(10))
        return true
    }

    /// Whether to ask now, in `version`.
    func isDue(version: String, at date: Date) -> Bool {
        guard daysUsed.count >= Self.daysBeforeAsking, askedVersion != version else { return false }
        guard let askedDate else { return true }
        return date.timeIntervalSince(askedDate) >= Double(Self.daysBetweenAsking) * 24 * 60 * 60
    }

    mutating func asked(version: String, at date: Date) {
        askedVersion = version
        askedDate = date
    }
}

extension AppModel {
    /// Whether these changes finish an issue: closed as completed, or moved into a done column. Not cancelled.
    func finishesWork(_ mutations: [Mutation]) -> Bool {
        mutations.contains { mutation in
            mutation.finishesWork { projectId, optionId in
                statusOptions(projectId: projectId).first { $0.id == optionId }?.statusCategory
            }
        }
    }
}

extension Mutation {
    /// Whether this change finishes an issue: closes it as completed, or moves it into a column whose `category` (of an
    /// option in a project) is done. Not one closed as not planned, or moved into a cancelled column.
    func finishesWork(category: (_ projectId: String, _ optionId: String) -> StatusCategory?) -> Bool {
        switch self {
        case .setState(let change):
            change.closed && change.reason != StatusCategory.canceled.closeReason
        case .setField(let change):
            change.kind == .status && change.optionId.flatMap { category(change.projectId, $0) } == .completed
        default:
            false
        }
    }
}
