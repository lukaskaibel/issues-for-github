#if os(macOS)
import Foundation

extension AppModel {
    private static let sharingAskedKey = "auth.sharingAsked"

    /// Signed in with the GitHub CLI, the token lives in `gh`, not in iCloud Keychain. Asks once whether to put
    /// it there so the iPhone and iPad sign in by themselves.
    func offerLoginSharingIfUseful() {
        guard signedIn, !isDemo, auth.method == .githubCLI, KeychainTokenStore.canShare,
              !UserDefaults.standard.bool(forKey: Self.sharingAskedKey),
              KeychainTokenStore.readShared() == nil else { return }
        offerLoginSharing = true
    }

    func answerLoginSharing(_ share: Bool) {
        UserDefaults.standard.set(true, forKey: Self.sharingAskedKey)
        offerLoginSharing = false
        guard share else { return }
        shareLoginWithOtherDevices()
    }

    func shareLoginWithOtherDevices() {
        let auth = self.auth
        Task {
            let shared: Bool
            if auth.method == .githubCLI {
                shared = (try? await auth.shareGitHubCLILogin()) ?? false
            } else {
                shared = KeychainTokenStore.readShared() != nil
            }
            status.post(shared
                ? Notice(title: String(localized: .loginSharedTitle), message: String(localized: .loginSharedMessage))
                : Notice(title: String(localized: .loginNotSharedTitle), message: String(localized: .loginNotSharedMessage), isWarning: true))
        }
    }

    /// Whether the iPhone and iPad can already use this Mac's login.
    var loginIsShared: Bool {
        KeychainTokenStore.readShared() != nil
    }
}
#endif
