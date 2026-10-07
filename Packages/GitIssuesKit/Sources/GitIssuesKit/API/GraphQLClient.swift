import Foundation
import os

public struct GraphQLErrorItem: Decodable, Sendable, Hashable {
    public var message: String
    public var type: String?
}

public enum APIError: Error, LocalizedError, Sendable {
    case noToken
    case unauthorized
    case offline(String)
    case rateLimited
    case http(Int, String)
    case graphql([GraphQLErrorItem])
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .noToken: String(localized: .errorNotSignedIn)
        case .unauthorized: String(localized: .errorSignInRejected)
        case .offline(let detail): String(localized: .errorCantReachGitHub(detail: detail))
        case .rateLimited: String(localized: .errorRateLimited)
        case .http(let code, _): String(localized: .errorGitHubReturnedError(code: code))
        case .graphql(let items): items.map(\.message).joined(separator: " ")
        case .decoding(let detail): String(localized: .errorUnexpectedResponse(detail: detail))
        }
    }

    /// Worth retrying later without changing anything.
    public var isTransient: Bool {
        switch self {
        case .offline, .rateLimited: true
        case .http(let code, _): code >= 500
        default: false
        }
    }

    /// The thing the request referred to no longer exists (deleted, transferred, or access removed).
    public var isNotFound: Bool {
        switch self {
        case .graphql(let items): items.contains { $0.type == "NOT_FOUND" }
        case .http(let code, _): code == 404
        default: false
        }
    }
}

public protocol TokenSource: Sendable {
    func token() async throws -> String
}

public final class GraphQLClient: Sendable {
    private let tokenSource: any TokenSource
    private let session: URLSession
    private let endpoint = URL(string: "https://api.github.com/graphql")!

    public init(tokenSource: any TokenSource, session: URLSession? = nil) {
        self.tokenSource = tokenSource
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    #if DEBUG
    /// Lets development builds rehearse being offline without touching the network settings.
    public static let simulateOffline = OSAllocatedUnfairLock(initialState: false)
    #endif

    private struct Envelope<T: Decodable>: Decodable {
        var data: T?
        var errors: [GraphQLErrorItem]?
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Runs a query or mutation. With `allowPartial`, a response that carries both data and errors
    /// (for example one inaccessible node in a list) returns the data instead of throwing.
    public func run<T: Decodable>(
        _ query: String,
        variables: [String: Any?] = [:],
        allowPartial: Bool = false,
        as type: T.Type = T.self
    ) async throws -> T {
        #if DEBUG
        if Self.simulateOffline.withLock({ $0 }) { throw APIError.offline("Simulated for testing.") }
        #endif
        let token = try await tokenSource.token()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("GitIssues-Mac", forHTTPHeaderField: "User-Agent")
        let cleaned = variables.mapValues { $0 ?? NSNull() }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": cleaned])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.offline(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.offline(String(localized: .errorNoResponse))
        }
        switch http.statusCode {
        case 200: break
        case 401: throw APIError.unauthorized
        case 403, 429:
            let text = String(data: data, encoding: .utf8) ?? ""
            if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || text.contains("rate limit") {
                throw APIError.rateLimited
            }
            throw APIError.http(http.statusCode, text)
        default:
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let envelope: Envelope<T>
        do {
            envelope = try Self.decoder.decode(Envelope<T>.self, from: data)
        } catch {
            // A failed mutation comes back as {"data": {"x": null}, "errors": [...]}, which may not decode as T.
            if let errors = try? Self.decoder.decode(Envelope<EmptyData>.self, from: data).errors, !errors.isEmpty {
                throw Self.classify(errors)
            }
            throw APIError.decoding(String(describing: error))
        }
        if let errors = envelope.errors, !errors.isEmpty {
            if allowPartial, let data = envelope.data { return data }
            throw Self.classify(errors)
        }
        guard let result = envelope.data else {
            throw APIError.decoding(String(localized: .errorEmptyResponse))
        }
        return result
    }

    private struct EmptyData: Decodable {}

    private static func classify(_ errors: [GraphQLErrorItem]) -> APIError {
        if errors.contains(where: { $0.type == "RATE_LIMITED" }) { return .rateLimited }
        return .graphql(errors)
    }

    // MARK: REST

    private let restBase = URL(string: "https://api.github.com")!

    /// Calls GitHub's REST API, for the few things GraphQL can't do (notifications). Returns the body and the
    /// response for 2xx and 304; anything else throws, mapped like the GraphQL errors.
    public func rest(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        json: [String: Any]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        #if DEBUG
        if Self.simulateOffline.withLock({ $0 }) { throw APIError.offline("Simulated for testing.") }
        #endif
        let token = try await tokenSource.token()
        var components = URLComponents(url: restBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitIssues-Mac", forHTTPHeaderField: "User-Agent")
        // GitHub answers 304 to a conditional request only when the cache stays out of the way.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.offline(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.offline(String(localized: .errorNoResponse))
        }
        switch http.statusCode {
        case 200..<300, 304:
            return (data, http)
        case 401:
            throw APIError.unauthorized
        case 403, 429:
            let text = String(data: data, encoding: .utf8) ?? ""
            if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || text.contains("rate limit") {
                throw APIError.rateLimited
            }
            throw APIError.http(http.statusCode, text)
        default:
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
