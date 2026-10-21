import Foundation
import Models
import os

/// What went wrong with a backend call, before a service turns it into an `AccountProblem`.
public enum APIFailure: Error, Sendable, Equatable {
    case offline
    case timedOut
    case cancelled
    /// 401 even after one fresh token, or no session to get a token from.
    case signedOut
    case forbidden
    /// 404 not_registered: the token is fine but the account doesn't exist yet.
    case notRegistered
    case rateLimited(retryAfterSeconds: Int)
    case unavailable(retryAfterSeconds: Int?)
    case serverError
    case updateRequired
    /// 2xx with a body that doesn't match the contract, or a response that isn't HTTP.
    case invalidResponse
    /// Any other 4xx: the request itself was wrong.
    case rejected(code: String)
    // 24b
    /// 403 attestation_required: register a new App Attest key, then retry once.
    case attestationRequired
    /// This device can't make an App Attest assertion (a simulator or an unsupported device).
    case attestationUnavailable
    /// 409 idempotency_conflict: the key was used for a different request. An app bug.
    case idempotencyConflict
    /// 409 action_in_progress: still running or being checked.
    case actionInProgress(retryAfterSeconds: Int)
    /// 429 quota_exceeded: an allowance is used up until `resetAt`.
    case quotaExceeded(category: String, resetAt: Date?, retryAfterSeconds: Int)
    /// 503 feature_paused: switched off on the server, or its spending ceiling is reached.
    case featurePaused(feature: String?, retryAfterSeconds: Int?)
}

/// Signs a paid request (24b): the App Attest headers for one try. Called again for every try,
/// because each assertion's counter must be higher than the last.
public protocol RequestSigner: Sendable {
    func headers(for endpoint: APIV1.Endpoint, idempotencyKey: String, body: Data) async throws(APIFailure)
        -> [String: String]
}

/// One step of a call, for the debug gateway screen and tests. Never holds a token or a body.
public enum APIEvent: Sendable, Equatable {
    case sent(endpoint: String, attempt: Int)
    case received(endpoint: String, status: Int, code: String?)
    case refreshedToken(endpoint: String)
    case retrying(endpoint: String, after: Duration, reason: String)
    case failed(endpoint: String, failure: APIFailure)
}

/// Bounded retries (SECURITY_STANDARD 4: every request has a timeout, cancellation and bounded
/// retries). Phase 26 tunes these against the real backend.
public struct RetryPolicy: Sendable, Equatable {
    /// Tries per call, the first one included. A refreshed token after a 401 doesn't count.
    public var maxAttempts: Int
    /// Backoff before the second try; doubles each time, up to `maxDelay`.
    public var baseDelay: Duration
    public var maxDelay: Duration
    /// A 429 or 503 whose Retry-After is this short is waited out and retried; a longer one is
    /// handed to the screen, which says when to try again.
    public var longestRetryAfterToWait: Duration
    /// Each try's timeout.
    public var requestTimeout: Duration

    public init(
        maxAttempts: Int = 3, baseDelay: Duration = .milliseconds(400), maxDelay: Duration = .seconds(4),
        longestRetryAfterToWait: Duration = .seconds(3), requestTimeout: Duration = .seconds(15)
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.longestRetryAfterToWait = longestRetryAfterToWait
        self.requestTimeout = requestTimeout
    }

    public static let standard = RetryPolicy()
}

/// Sends contract requests to the backend over `URLSession`: the bearer token, one token refresh
/// on a 401, bounded retries with backoff for safe requests, Retry-After on 429 and 503, and
/// mapping every other failure to an `APIFailure`. It logs nothing personal and no tokens.
public final class APIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let auth: any AuthProvider
    private let policy: RetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void
    private let onEvent: @Sendable (APIEvent) -> Void
    private static let logger = Logger(subsystem: "com.jsayram.niftyoutfitnook", category: "gateway")

    public init(
        baseURL: URL, session: URLSession, auth: any AuthProvider, policy: RetryPolicy = .standard,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onEvent: @escaping @Sendable (APIEvent) -> Void = { _ in }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.auth = auth
        self.policy = policy
        self.sleep = sleep
        self.onEvent = onEvent
    }

    /// A session for the backend: nothing cached or stored on disk, no cookies, TLS 1.2 or later.
    public static func makeSession(policy: RetryPolicy = .standard, protocolClasses: [AnyClass] = []) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = policy.requestTimeout.seconds
        configuration.timeoutIntervalForResource = policy.requestTimeout.seconds * Double(policy.maxAttempts) + 10
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        if !protocolClasses.isEmpty {
            configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? [])
        }
        return URLSession(configuration: configuration)
    }

    public func send<Response: Decodable>(_ endpoint: APIV1.Endpoint, as type: Response.Type) async throws(APIFailure)
        -> Response
    {
        try await send(endpoint, body: Optional<APIV1.SessionRequest>.none, as: type)
    }

    public func send<Body: Encodable, Response: Decodable>(
        _ endpoint: APIV1.Endpoint, body: Body?, as type: Response.Type
    ) async throws(APIFailure) -> Response {
        try await send(endpoint, body: body, idempotencyKey: nil, signer: nil, as: type)
    }

    /// A paid request: every try carries the same `idempotencyKey`, so the server never runs or
    /// counts a retry twice, and its own App Attest assertion from `signer`.
    public func send<Body: Encodable, Response: Decodable>(
        _ endpoint: APIV1.Endpoint, body: Body?, idempotencyKey: String?, signer: (any RequestSigner)?,
        as type: Response.Type
    ) async throws(APIFailure) -> Response {
        let payload: Data?
        if let body {
            guard let data = try? APIV1.encoder().encode(body), data.count <= APIV1.maxBodyBytes else {
                throw fail(endpoint, .rejected(code: APIV1.ErrorCode.payloadTooLarge.rawValue))
            }
            payload = data
        } else {
            payload = nil
        }

        var attempt = 0
        var refreshedToken = false
        var forceRefresh = false
        while true {
            if Task.isCancelled { throw fail(endpoint, .cancelled) }
            attempt += 1
            var request = URLRequest(url: baseURL.appending(path: endpoint.path))
            request.httpMethod = endpoint.method
            request.timeoutInterval = policy.requestTimeout.seconds
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let payload {
                request.httpBody = payload
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            if endpoint.requiresAuth {
                do {
                    let token = try await auth.token(forceRefresh: forceRefresh)
                    request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
                } catch {
                    throw fail(endpoint, error == .offline ? .offline : .signedOut)
                }
                forceRefresh = false
            }
            if let idempotencyKey {
                request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
                if let signer {
                    let headers: [String: String]
                    do {
                        headers = try await signer.headers(
                            for: endpoint, idempotencyKey: idempotencyKey, body: payload ?? Data())
                    } catch {
                        throw fail(endpoint, error)
                    }
                    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
                }
            }

            onEvent(.sent(endpoint: endpoint.id, attempt: attempt))
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError {
                let failure = Self.failure(for: error)
                if failure == .timedOut, endpoint.idempotent, attempt < policy.maxAttempts {
                    try await wait(backoff(attempt), endpoint, reason: "timed out")
                    continue
                }
                throw fail(endpoint, failure)
            } catch {
                throw fail(endpoint, Task.isCancelled ? .cancelled : .offline)
            }
            guard let http = response as? HTTPURLResponse else { throw fail(endpoint, .invalidResponse) }
            let envelope =
                (200..<300).contains(http.statusCode)
                ? nil : try? JSONDecoder().decode(APIV1.ErrorEnvelope.self, from: data)
            onEvent(.received(endpoint: endpoint.id, status: http.statusCode, code: envelope?.error.code))

            switch http.statusCode {
            case 200..<300:
                guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                    throw fail(endpoint, .invalidResponse)
                }
                return decoded
            case 401:
                // An expired or refused token: get a fresh one and try once more. A second 401
                // means the session itself is gone.
                guard endpoint.requiresAuth, !refreshedToken else { throw fail(endpoint, .signedOut) }
                refreshedToken = true
                forceRefresh = true
                attempt -= 1
                onEvent(.refreshedToken(endpoint: endpoint.id))
                continue
            case 403 where envelope?.error.code == APIV1.ErrorCode.attestationRequired.rawValue:
                throw fail(endpoint, .attestationRequired)
            case 403:
                throw fail(endpoint, .forbidden)
            case 409 where envelope?.error.code == APIV1.ErrorCode.idempotencyConflict.rawValue:
                throw fail(endpoint, .idempotencyConflict)
            case 409:
                // action_in_progress: the same key is safe to send again once it has finished.
                let retryAfter = Self.retryAfter(http, envelope) ?? 2
                if Duration.seconds(retryAfter) <= policy.longestRetryAfterToWait, attempt < policy.maxAttempts {
                    try await wait(.seconds(retryAfter), endpoint, reason: "still running, Retry-After \(retryAfter)s")
                    continue
                }
                throw fail(endpoint, .actionInProgress(retryAfterSeconds: retryAfter))
            case 429 where envelope?.error.code == APIV1.ErrorCode.quotaExceeded.rawValue:
                // Never waited out: the allowance comes back hours or days later.
                let resetAt = envelope?.error.resetAt.flatMap(APIV1.parseDate)
                throw fail(
                    endpoint,
                    .quotaExceeded(
                        category: envelope?.error.category ?? "", resetAt: resetAt,
                        retryAfterSeconds: Self.retryAfter(http, envelope) ?? 3600))
            case 503 where envelope?.error.code == APIV1.ErrorCode.featurePaused.rawValue:
                throw fail(
                    endpoint,
                    .featurePaused(feature: envelope?.error.feature, retryAfterSeconds: Self.retryAfter(http, envelope))
                )
            case 404 where envelope?.error.code == APIV1.ErrorCode.notRegistered.rawValue:
                throw fail(endpoint, .notRegistered)
            case 410:
                throw fail(endpoint, .updateRequired)
            case 429, 503:
                let retryAfter = Self.retryAfter(http, envelope)
                if let retryAfter, Duration.seconds(retryAfter) <= policy.longestRetryAfterToWait,
                    attempt < policy.maxAttempts
                {
                    try await wait(.seconds(retryAfter), endpoint, reason: "Retry-After \(retryAfter)s")
                    continue
                }
                if http.statusCode == 429 {
                    throw fail(endpoint, .rateLimited(retryAfterSeconds: retryAfter ?? 60))
                }
                throw fail(endpoint, .unavailable(retryAfterSeconds: retryAfter))
            case 500..<600:
                if endpoint.idempotent, attempt < policy.maxAttempts {
                    try await wait(backoff(attempt), endpoint, reason: "server error \(http.statusCode)")
                    continue
                }
                throw fail(endpoint, .serverError)
            default:
                throw fail(endpoint, .rejected(code: envelope?.error.code ?? String(http.statusCode)))
            }
        }
    }

    // MARK: Helpers

    private func fail(_ endpoint: APIV1.Endpoint, _ failure: APIFailure) -> APIFailure {
        onEvent(.failed(endpoint: endpoint.id, failure: failure))
        Self.logger.info("\(endpoint.id, privacy: .public) failed: \(String(describing: failure), privacy: .public)")
        return failure
    }

    private func wait(_ delay: Duration, _ endpoint: APIV1.Endpoint, reason: String) async throws(APIFailure) {
        onEvent(.retrying(endpoint: endpoint.id, after: delay, reason: reason))
        do {
            try await sleep(delay)
        } catch {
            throw fail(endpoint, .cancelled)
        }
    }

    /// 0.4 s, 0.8 s, 1.6 s... up to `maxDelay`, with up to a quarter added at random so many
    /// phones don't retry in step.
    func backoff(_ attempt: Int) -> Duration {
        let base = policy.baseDelay * (1 << max(0, min(attempt - 1, 10)))
        let capped = min(base, policy.maxDelay)
        return capped + capped * Double.random(in: 0...0.25)
    }

    static func retryAfter(_ response: HTTPURLResponse, _ envelope: APIV1.ErrorEnvelope?) -> Int? {
        if let header = response.value(forHTTPHeaderField: "Retry-After"), let seconds = Int(header), seconds >= 0 {
            return seconds
        }
        return envelope?.error.retryAfterSeconds
    }

    static func failure(for error: URLError) -> APIFailure {
        switch error.code {
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            .offline
        case .badServerResponse, .cannotParseResponse, .cannotDecodeContentData, .cannotDecodeRawData:
            .invalidResponse
        default: .offline
        }
    }
}

extension Duration {
    /// This duration in seconds, as a `TimeInterval`.
    var seconds: TimeInterval {
        let (whole, fraction) = components
        return TimeInterval(whole) + TimeInterval(fraction) / 1e18
    }
}

extension APIEvent {
    /// One line for the debug gateway screen. Names the endpoint and status, never a token.
    public var summary: String {
        switch self {
        case .sent(let endpoint, let attempt):
            attempt == 1 ? "→ \(endpoint)" : "→ \(endpoint) (try \(attempt))"
        case .received(let endpoint, let status, let code):
            "← \(endpoint) \(status)" + (code.map { " \($0)" } ?? "")
        case .refreshedToken(let endpoint):
            "↻ \(endpoint): fresh token, trying once more"
        case .retrying(let endpoint, let after, let reason):
            "⏱ \(endpoint): \(reason), retrying in \(after.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))"
        case .failed(let endpoint, let failure):
            "✕ \(endpoint): \(failure)"
        }
    }
}
