#if os(iOS)
import BackgroundTasks
import UIKit

extension AppModel {
    /// Syncs every 15 seconds while the app is in front. On the way to the background, queued changes are
    /// sent before iOS suspends the app, and a refresh is scheduled so the app opens up to date.
    func installLifecycleObservers() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let engine = self?.engine else { return }
                Task {
                    await engine.setPollInterval(15)
                    // Back in front: what's new in the Inbox right away (usually GitHub's free "nothing new").
                    await engine.refreshInbox()
                }
            }
        })
        lifecycleObservers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let engine = self?.engine else { return }
                Task { await engine.setPollInterval(60) }
            }
        })
        lifecycleObservers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnterBackground() }
        })
    }

    private func didEnterBackground() {
        guard signedIn, !isDemo else { return }
        BackgroundRefresh.schedule()
        guard pendingCount > 0 else { return }
        // Changes made just before locking the phone still go out; iOS grants a little time for that.
        let engine = self.engine
        var task: UIBackgroundTaskIdentifier = .invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Send queued changes") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        Task {
            // Leaving the app ends the moment to undo, so archived Inbox entries go out now too.
            try? await engine.pushPending()
            await engine.syncNow()
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }
    }

    /// One sync round while the app is in the background, when iOS offers the time.
    func backgroundRefresh() async {
        guard signedIn, !isDemo else { return }
        BackgroundRefresh.schedule()
        await engine.syncNow()
    }
}

enum BackgroundRefresh {
    static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "com.lukaskbl.GitIssues") + ".refresh"
    }

    /// Asks iOS for a refresh in about a quarter of an hour; it decides when, based on how the app is used.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        BGTaskScheduler.shared.submitTaskRequest(request) { _ in }
    }
}
#endif
