#if os(macOS)
import AppKit

extension AppModel {
    /// Syncs every 15 seconds while the app is in front and once a minute behind other apps.
    func installLifecycleObservers() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let engine = self?.engine else { return }
                Task {
                    await engine.setPollInterval(15)
                    // Back in front: what's new in the Inbox right away (usually GitHub's free "nothing new").
                    await engine.refreshInbox()
                }
            }
        })
        lifecycleObservers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let engine = self?.engine else { return }
                Task { await engine.setPollInterval(60) }
            }
        })
    }
}
#endif
