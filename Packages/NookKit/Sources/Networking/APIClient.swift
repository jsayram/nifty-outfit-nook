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
    /// A fresh token was still refused, or couldn't be had: the session is over and was ended on
    /// this phone (26).
    case sessionEnded(endpoint: String)
    case failed(endpoint: String, failure: APIFailure)
}

/// How long one call may take: each try, and all tries and waits together.
public struct EndpointTiming: Sendable, Equatable {
    /// One try. A hard limit, not just an idle one: a server that trickles bytes is cut off too.
    public var attemptTimeout: Duration
    /// Every try and every wait between them (PRD 11.7: 30 seconds unless the endpoint says more).
    public var deadline: Duration

    public init(attemptTimeout: Duration, deadline: Duration) {
        self.attemptTimeout = attemptTimeout
        self.deadline = deadline
    }
}

/// Timeouts, deadlines and bounded retries (SECURITY_STANDARD 4: every request has a timeout,
/// cancellation and bounded retries; PRD 11.7: a declared overall deadline, bounded attempts).
/// The rules, in `docs/network-resilience.md`:
/// - A try is cut off after `requestTimeout` (10 s), and a call after `overallDeadline` (30 s),
///   whichever endpoint timing the call uses. A paid text request has longer ones, and a try-on
///   picture the aggregate bound PRD 9.2.4 proposes, since its tries are short polls.
/// - Only requests that are safe to repeat are retried, and only after a timeout, a connection
///   lost on the way, a 5xx, a 429/503 with a short Retry-After, or "still running".
/// - Backoff doubles from `baseDelay` up to `maxDelay`, with up to a quarter added at random.
public struct RetryPolicy: Sendable, Equatable {
    /// Tries per call, the first one included. A refreshed token after a 401 doesn't count, and
    /// neither do polls of an action that is still running (the deadline bounds those).
    public var maxAttempts: Int
    /// Backoff before the second try; doubles each time, up to `maxDelay`.
    public var baseDelay: Duration
    public var maxDelay: Duration
    /// A 429 or 503 whose Retry-After is this short is waited out and retried; a longer one is
    /// handed to the screen, which says when to try again.
    public var longestRetryAfterToWait: Duration
    /// Each try's timeout, for endpoints without a timing of their own.
    public var requestTimeout: Duration
    /// All tries and waits of one call, for endpoints without a timing of their own.
    public var overallDeadline: Duration
    /// Timings by endpoint ID, for the endpoints that need longer.
    public var timingOverrides: [String: EndpointTiming]

    /// The timings that differ from the default. A paid text request waits for the server's own
    /// 30 second deadline and a little more; a try-on picture gets the 360 seconds PRD 9.2.4
    /// proposes for a parent job (33a confirms it), each try being a short call.
    public static let defaultTimingOverrides: [String: EndpointTiming] = [
        APIV1.style.id: EndpointTiming(attemptTimeout: .seconds(40), deadline: .seconds(45)),
        APIV1.tryOn.id: EndpointTiming(attemptTimeout: .seconds(30), deadline: .seconds(360)),
    ]

    public init(
        maxAttempts: Int = 3, baseDelay: Duration = .milliseconds(400), maxDelay: Duration = .seconds(4),
        longestRetryAfterToWait: Duration = .seconds(3), requestTimeout: Duration = .seconds(10),
        overallDeadline: Duration = .seconds(30), timingOverrides: [String: EndpointTiming]? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.longestRetryAfterToWait = longestRetryAfterToWait
        self.requestTimeout = requestTimeout
        self.overallDeadline = overallDeadline
        self.timingOverrides = timingOverrides ?? Self.defaultTimingOverrides
    }

    public static let standard = RetryPolicy()

    public func timing(for endpoint: APIV1.Endpoint) -> EndpointTiming {
        timingOverrides[endpoint.id] ?? EndpointTiming(attemptTimeout: requestTimeout, deadline: overallDeadline)
    }

    /// The longest any call can take, for the session's own resource limit.
    var longestDeadline: Duration {
        timingOverrides.values.reduce(overallDeadline) { max($0, $1.deadline) }
    }
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
        // The client sets each request's own timeout and cuts it off at the deadline, so these two
        // only have to be no shorter than the longest of those.
        configuration.timeoutIntervalForRequest = policy.longestDeadline.seconds
        configuration.timeoutIntervalForResource = policy.longestDeadline.seconds + 10
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

        let timing = policy.timing(for: endpoint)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timing.deadline)
        /// Whether a wait of `delay` and then another try can still finish before the deadline.
        func fits(_ delay: Duration) -> Bool { clock.now.advanced(by: delay) < deadline }

        var attempt = 0
        var sends = 0
        var refreshedToken = false
        var forceRefresh = false
        while true {
            if Task.isCancelled { throw fail(endpoint, .cancelled) }
            if clock.now >= deadline { throw fail(endpoint, .timedOut) }
            attempt += 1
            sends += 1
            var request = URLRequest(url: baseURL.appending(path: endpoint.path))
            request.httpMethod = endpoint.method
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
                    switch error {
                    case .offline:
                        throw fail(endpoint, .offline)
                    case .signedOut, .cancelled:
                        throw fail(endpoint, .signedOut)
                    case .failed:
                        // A fresh token that can't be had means the session is over. Any other
                        // hiccup in the sign-in service is the service's, not hers.
                        guard forceRefresh else { throw fail(endpoint, .unavailable(retryAfterSeconds: nil)) }
                        await endSession(endpoint)
                        throw fail(endpoint, .signedOut)
                    }
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
            // This try gets its full timeout, or what is left of the call's deadline.
            let allowed = min(timing.attemptTimeout, clock.now.duration(to: deadline))
            request.timeoutInterval = allowed.seconds

            onEvent(.sent(endpoint: endpoint.id, attempt: sends))
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await fetch(request, within: allowed)
            } catch let error as URLError {
                let failure = Self.failure(for: error)
                // A try that timed out, or whose connection dropped on the way, may or may not
                // have reached the server. A request that is safe to repeat (every paid one
                // carries its Idempotency-Key) is tried again, a bounded number of times. Having
                // no connection at all (`notConnectedToInternet`) is not retried: nothing was sent.
                let mayHaveBeenSent = failure == .timedOut || error.code == .networkConnectionLost
                if mayHaveBeenSent, endpoint.idempotent, attempt < policy.maxAttempts {
                    let delay = backoff(attempt)
                    if fits(delay) {
                        try await wait(
                            delay, endpoint, reason: failure == .timedOut ? "timed out" : "connection lost")
                        continue
                    }
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
                // means the session itself is gone, so it is ended here and she signs in again.
                guard endpoint.requiresAuth else { throw fail(endpoint, .signedOut) }
                guard !refreshedToken else {
                    await endSession(endpoint)
                    throw fail(endpoint, .signedOut)
                }
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
                // action_in_progress: the job is still running, or its outcome is being checked.
                // Asking again with the same key is safe, and it isn't a failed try, so it is
                // polled every Retry-After (1 to 10 seconds) until the deadline.
                let retryAfter = Self.retryAfter(http, envelope) ?? 2
                let delay = Duration.seconds(min(max(retryAfter, 1), 10))
                if fits(delay) {
                    attempt -= 1
                    try await wait(delay, endpoint, reason: "still running, asking again")
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
                // Retry-After is a promise not to be asked sooner, so a short one is waited out
                // exactly, and a long one goes to the screen. A 503 without one gets the same
                // backoff as a 5xx, for requests that are safe to repeat.
                let retryAfter = Self.retryAfter(http, envelope)
                let delay = retryAfter.map { Duration.seconds($0) }
                if let delay, delay <= policy.longestRetryAfterToWait, attempt < policy.maxAttempts, fits(delay) {
                    try await wait(delay, endpoint, reason: "Retry-After \(retryAfter ?? 0)s")
                    continue
                }
                if http.statusCode == 503, retryAfter == nil, endpoint.idempotent, attempt < policy.maxAttempts {
                    let pause = backoff(attempt)
                    if fits(pause) {
                        try await wait(pause, endpoint, reason: "unavailable, no Retry-After")
                        continue
                    }
                }
                if http.statusCode == 429 {
                    throw fail(endpoint, .rateLimited(retryAfterSeconds: retryAfter ?? 60))
                }
                throw fail(endpoint, .unavailable(retryAfterSeconds: retryAfter))
            case 500..<600:
                if endpoint.idempotent, attempt < policy.maxAttempts {
                    let delay = backoff(attempt)
                    if fits(delay) {
                        try await wait(delay, endpoint, reason: "server error \(http.statusCode)")
                        continue
                    }
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

    /// A response, or an error. `URLResponse` is immutable, so handing it between tasks is safe.
    private struct Fetched: @unchecked Sendable {
        var data: Data
        var response: URLResponse
    }

    /// One try, cut off after `limit` however the server is behaving: a request that is racing a
    /// timer inside a task group, so nothing is left running when it ends (and she leaving the
    /// screen cancels both). `URLRequest.timeoutInterval` alone only limits silence, not a slow
    /// trickle.
    private func fetch(_ request: URLRequest, within limit: Duration) async throws -> (Data, URLResponse) {
        let session = session
        let fetched = try await withThrowingTaskGroup(of: Fetched?.self) { group in
            group.addTask {
                let (data, response) = try await session.data(for: request)
                return Fetched(data: data, response: response)
            }
            group.addTask {
                try await Task.sleep(for: limit)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            guard let fetched = first else { throw URLError(.timedOut) }
            return fetched
        }
        return (fetched.data, fetched.response)
    }

    /// Ends the session on this phone after a fresh token was refused: she is asked to sign in
    /// again, and nothing in her closet changes.
    private func endSession(_ endpoint: APIV1.Endpoint) async {
        await auth.signOut()
        onEvent(.sessionEnded(endpoint: endpoint.id))
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

    /// Retry-After as whole seconds, from either form HTTP allows: a number of seconds, or a date
    /// (RFC 9110 section 10.2.3). A date in the past means now. Anything else is ignored.
    static func retryAfter(_ response: HTTPURLResponse, _ envelope: APIV1.ErrorEnvelope?, now: Date = Date()) -> Int? {
        if let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) {
            if let seconds = Int(header), seconds >= 0 { return seconds }
            if let date = HTTPDate.parse(header) { return max(0, Int(date.timeIntervalSince(now).rounded(.up))) }
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
        case .sessionEnded(let endpoint):
            "✕ \(endpoint): signed out, the session is over"
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

/// The date form of Retry-After: "Wed, 21 Oct 2026 07:28:00 GMT".
enum HTTPDate {
    static func parse(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.date(from: text)
    }
}
