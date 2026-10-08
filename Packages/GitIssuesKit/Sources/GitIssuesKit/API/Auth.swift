import Foundation
import Security

/// Keeps the GitHub token in the keychain.
///
/// The token is stored once for all of the user's devices: as a synchronizable item in iCloud Keychain, in the
/// app's keychain access group, so signing in on the Mac signs in the iPhone and iPad too. Builds that are not
/// signed with a team have no access group; they keep the token on this device only.
public enum KeychainTokenStore {
    private static let service = "com.lukaskbl.GitIssues.github-token"
    private static let account = "github.com"

    private static func query(shared: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if shared {
            query[kSecAttrSynchronizable as String] = true
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private static func read(shared: Bool) -> String? {
        var query = query(shared: shared)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// The token, preferring the one shared with the user's other devices.
    public static func read() -> String? {
        read(shared: true) ?? read(shared: false)
    }

    /// The token another of the user's devices shared through iCloud Keychain, if any.
    public static func readShared() -> String? {
        read(shared: true)
    }

    @discardableResult
    private static func save(_ token: String, shared: Bool) -> Bool {
        SecItemDelete(query(shared: shared) as CFDictionary)
        var attributes = query(shared: shared)
        attributes[kSecValueData as String] = Data(token.utf8)
        // Readable after the first unlock, so syncing in the background works while the device is locked.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Saves the token for all of the user's devices, or for this one where sharing isn't possible.
    /// Returns whether it is shared.
    @discardableResult
    public static func save(_ token: String) -> Bool {
        if save(token, shared: true) {
            SecItemDelete(query(shared: false) as CFDictionary)
            return true
        }
        save(token, shared: false)
        return false
    }

    /// Saves the token for the user's other devices only, leaving this device's way of signing in alone.
    @discardableResult
    public static func share(_ token: String) -> Bool {
        save(token, shared: true)
    }

    /// Forgets the token on this device; with `everywhere`, also the copy shared with the other devices.
    public static func delete(everywhere: Bool) {
        SecItemDelete(query(shared: false) as CFDictionary)
        if everywhere { SecItemDelete(query(shared: true) as CFDictionary) }
    }

    #if os(macOS)
    /// Whether this build may use iCloud Keychain: it needs a keychain access group, which needs a team.
    public static var canShare: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) != nil
    }
    #endif

    /// Moves a token saved by an earlier version (on this device only) to the shared place, when it can.
    public static func migrateToShared() {
        guard read(shared: true) == nil, let local = read(shared: false) else { return }
        if save(local, shared: true) { SecItemDelete(query(shared: false) as CFDictionary) }
    }
}

#if os(macOS)
/// Reads the token of an existing GitHub CLI login. Meant for development builds.
public enum GitHubCLI {
    public static func executableURL() -> URL? {
        // Inside the App Sandbox (the App Store build) `gh` inherits the sandbox and can't read its own login.
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else { return nil }
        return ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static var isAvailable: Bool { executableURL() != nil }

    public static func token() async throws -> String {
        guard let url = executableURL() else { throw APIError.noToken }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = url
            process.arguments = ["auth", "token"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0, !token.isEmpty {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: APIError.noToken)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: APIError.noToken)
            }
        }
    }
}
#endif

/// A fixed token, for checking one before it is saved.
struct FixedToken: TokenSource {
    var value: String
    func token() async throws -> String { value }
}

/// The app's single source of truth for the GitHub token.
public actor AuthStore: TokenSource {
    public enum Method: String, Sendable {
        case keychain
        case githubCLI
    }

    private static let methodKey = "auth.method"
    /// Set when the user signed out on this device while their other devices stay signed in, so the shared
    /// login is not picked up again by itself.
    private static let declinedKey = "auth.sharedLoginDeclined"
    private var cached: String?

    public init() {}

    public nonisolated var method: Method? {
        let stored = UserDefaults.standard.string(forKey: Self.methodKey).flatMap(Method.init)
        #if os(macOS)
        // A CLI login only counts while the CLI is usable. The App Store build can inherit this setting from a
        // development build, because macOS moves the preferences into the sandbox container on first launch.
        if stored == .githubCLI, !GitHubCLI.isAvailable { return nil }
        #endif
        return stored
    }

    public nonisolated var isSignedIn: Bool { method != nil }

    /// Signs in with the login another of the user's devices shared through iCloud Keychain, unless the user
    /// signed out of it on this device. Returns whether this device is signed in now.
    @discardableResult
    public nonisolated func adoptSharedLogin(force: Bool = false) -> Bool {
        if isSignedIn { return true }
        guard force || !UserDefaults.standard.bool(forKey: Self.declinedKey),
              KeychainTokenStore.readShared() != nil else { return false }
        UserDefaults.standard.set(Method.keychain.rawValue, forKey: Self.methodKey)
        UserDefaults.standard.removeObject(forKey: Self.declinedKey)
        return true
    }

    /// Whether a login shared by another device is waiting to be used here.
    public nonisolated var sharedLoginAvailable: Bool {
        KeychainTokenStore.readShared() != nil
    }

    public func token() async throws -> String {
        if let cached { return cached }
        let token: String
        switch method {
        case .keychain:
            guard let stored = KeychainTokenStore.read() else { throw APIError.noToken }
            token = stored
        case .githubCLI:
            #if os(macOS)
            token = try await GitHubCLI.token()
            #else
            throw APIError.noToken
            #endif
        case nil:
            throw APIError.noToken
        }
        cached = token
        return token
    }

    /// Checks a token with GitHub before it is saved, so a typo is caught at once.
    public static func validate(_ token: String) async throws {
        let api = GitHubAPI(client: GraphQLClient(tokenSource: FixedToken(value: token)))
        _ = try await api.viewerAndProjects()
    }

    public func signIn(token: String) {
        KeychainTokenStore.save(token)
        UserDefaults.standard.set(Method.keychain.rawValue, forKey: Self.methodKey)
        UserDefaults.standard.removeObject(forKey: Self.declinedKey)
        cached = token
    }

    #if os(macOS)
    public func signInWithGitHubCLI() async throws {
        cached = try await GitHubCLI.token()
        UserDefaults.standard.set(Method.githubCLI.rawValue, forKey: Self.methodKey)
        UserDefaults.standard.removeObject(forKey: Self.declinedKey)
    }

    /// Puts the GitHub CLI's token into iCloud Keychain, so the iPhone and iPad sign in with it.
    public func shareGitHubCLILogin() async throws -> Bool {
        let token = try await GitHubCLI.token()
        return KeychainTokenStore.share(token)
    }
    #endif

    /// Signs this device out. With `everywhere`, the shared login is removed too, which signs out the
    /// user's other devices as well.
    public func signOut(everywhere: Bool = false) {
        KeychainTokenStore.delete(everywhere: everywhere)
        UserDefaults.standard.removeObject(forKey: Self.methodKey)
        if everywhere {
            UserDefaults.standard.removeObject(forKey: Self.declinedKey)
        } else if KeychainTokenStore.readShared() != nil {
            UserDefaults.standard.set(true, forKey: Self.declinedKey)
        }
        cached = nil
    }

    /// Drops the in-memory copy so the next request re-reads it (after a 401, for instance).
    public func invalidateCache() {
        cached = nil
    }
}

/// GitHub's OAuth device flow: the user enters a short code on github.com and the app polls for the token.
public struct DeviceFlow: Sendable {
    public struct Code: Sendable {
        public var deviceCode: String
        public var userCode: String
        public var verificationURL: URL
        public var interval: TimeInterval
        public var expiresAt: Date
    }

    public enum FlowError: Error, LocalizedError {
        case notConfigured
        case expired
        case denied
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: String(localized: .errorNoOAuthClientID)
            case .expired: String(localized: .errorCodeExpired)
            case .denied: String(localized: .errorAccessDenied)
            case .failed(let detail): detail
            }
        }
    }

    public let clientID: String
    public static let scopes = "repo project read:org"

    public init(clientID: String) {
        self.clientID = clientID
    }

    /// The client ID comes from the app's Info.plist key `GitHubClientID`.
    public static var configuredClientID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String
        return (value?.isEmpty == false) ? value : nil
    }

    public func start() async throws -> Code {
        guard !clientID.isEmpty else { throw FlowError.notConfigured }
        let json = try await post("https://github.com/login/device/code", ["client_id": clientID, "scope": Self.scopes])
        guard let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let uri = (json["verification_uri"] as? String).flatMap(URL.init(string:)) else {
            throw FlowError.failed((json["error_description"] as? String) ?? String(localized: .errorNoCodeReturned))
        }
        let interval = (json["interval"] as? Double) ?? 5
        let expires = (json["expires_in"] as? Double) ?? 900
        return Code(deviceCode: deviceCode, userCode: userCode, verificationURL: uri, interval: interval, expiresAt: Date().addingTimeInterval(expires))
    }

    /// Polls until the user approves on github.com, then returns the access token.
    public func waitForToken(_ code: Code) async throws -> String {
        var interval = code.interval
        while Date() < code.expiresAt {
            try await Task.sleep(for: .seconds(interval))
            let json = try await post("https://github.com/login/oauth/access_token", [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let token = json["access_token"] as? String { return token }
            switch json["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "expired_token": throw FlowError.expired
            case "access_denied": throw FlowError.denied
            default: throw FlowError.failed((json["error_description"] as? String) ?? String(localized: .errorSignInFailed))
            }
        }
        throw FlowError.expired
    }

    private func post(_ url: String, _ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
