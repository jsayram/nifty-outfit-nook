import Foundation
import Synchronization

/// How the fake backend behaves, to exercise every way the real one, or the network, can fail.
public enum FakeBackendMode: Sendable, Hashable {
    /// Answers as the contract says.
    case normal
    /// Answers correctly, after a delay.
    case slow(seconds: Double)
    /// Never answers, so the request times out.
    case timeout
    /// Answers, but one byte every 100 ms: never silent for long, and never done. Only a hard
    /// limit on the whole try ends it (26).
    case trickle
    /// Refuses the next token it sees as expired (and keeps refusing that one), like a token that
    /// expired on the way. A fresh token works.
    case expiredToken
    /// 403 forbidden on endpoints that need a token.
    case forbidden
    /// 429 with Retry-After.
    case rateLimited(retryAfterSeconds: Int)
    /// 500 internal.
    case serverError
    /// 503 unavailable, with Retry-After when given.
    case unavailable(retryAfterSeconds: Int?)
    /// 200 with a body that isn't valid JSON.
    case malformedJSON
    /// No connection at all.
    case offline
    /// Does the work, then the answer never arrives (a timeout), like a dropped connection after
    /// the server finished. The client's retry with the same Idempotency-Key gets it back (24b).
    case answerLost
    /// Does the work, then the connection drops before the answer arrives (`networkConnectionLost`),
    /// like a phone leaving Wi-Fi mid-request. Retrying with the same key gets the answer back (26).
    case connectionLost
    /// Paid endpoints answer 409 action_in_progress with Retry-After: the job is still running,
    /// or its outcome is being checked (26).
    case actionInProgress(retryAfterSeconds: Int)
    /// Paid endpoints refuse every App Attest assertion with 403 attestation_required (24b).
    case attestationRejected
}

/// What the fake answers one request with.
enum FakeReply: Sendable {
    case respond(status: Int, headers: [String: String], body: Data, delay: Duration)
    case trickle(status: Int, headers: [String: String], body: Data)
    case fail(URLError.Code, delay: Duration)
    case hang
}

/// An in-process stand-in for the Convex gateway, served through `FakeBackendURLProtocol`. Its
/// answers are built from the same contract types the client decodes (`APIV1`), and its checks
/// follow the real gateway's: route and method, then the token, then content type, size and the
/// request schema with unknown fields rejected.
public final class FakeBackend: Sendable {
    /// A host of its own (under .invalid, which never resolves), so tests can run side by side.
    public let host: String
    public var baseURL: URL { URL(string: "https://\(host)") ?? URL(filePath: "/") }

    struct State {
        var mode = FakeBackendMode.normal
        /// Requests left before the mode goes back to normal; nil keeps it.
        var remaining: Int?
        var principals: [String: (id: String, createdAt: Date)] = [:]
        var refusedTokens: Set<String> = []
        var requestCount = 0
        /// 24b: allowances, switches, keys and paid actions (FakeBackend+Limits.swift).
        var limits = FakeLimits()
        var ledger = FakeLedger()
        /// 24c: account deletions (FakeBackend+Deletion.swift).
        var deletions = FakeDeletions()
        /// 24d: support notes (FakeBackend+Support.swift).
        var support = FakeSupport()
    }

    let state = Mutex(State())
    let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.host = "fake-\(FakeToken.randomHex(6)).backend.invalid"
        self.now = now
        FakeBackendURLProtocol.register(self)
    }

    deinit {
        FakeBackendURLProtocol.unregister(host)
    }

    /// Changes how it behaves: for the next `times` requests, or until changed when nil.
    public func setMode(_ mode: FakeBackendMode, times: Int? = nil) {
        state.withLock {
            $0.mode = mode
            $0.remaining = times
        }
    }

    public var mode: FakeBackendMode { state.withLock { $0.mode } }
    public var requestCount: Int { state.withLock { $0.requestCount } }
    public var accountCount: Int { state.withLock { $0.principals.count } }

    // MARK: Answering

    func reply(to request: URLRequest, body: Data?) -> FakeReply {
        let mode = state.withLock { state -> FakeBackendMode in
            state.requestCount += 1
            let mode = state.mode
            if let remaining = state.remaining {
                if remaining <= 1 {
                    state.mode = .normal
                    state.remaining = nil
                } else {
                    state.remaining = remaining - 1
                }
            }
            return mode
        }
        let id = "req_" + FakeToken.randomHex(16)
        let endpoint = APIV1.endpoints.first { $0.path == request.url?.path() && $0.method == request.httpMethod }

        switch mode {
        case .offline: return .fail(.notConnectedToInternet, delay: .milliseconds(50))
        case .timeout: return .hang
        case .malformedJSON: return json(200, Data(#"{"user": {"id": "usr_"#.utf8), id)
        case .serverError: return error(.internal, id)
        case .rateLimited(let seconds): return error(.rateLimited, id, retryAfter: seconds)
        case .unavailable(let seconds): return error(.unavailable, id, retryAfter: seconds)
        case .forbidden where endpoint?.requiresAuth == true: return error(.forbidden, id)
        case .attestationRejected where endpoint?.paid == true: return error(.attestationRequired, id)
        case .actionInProgress(let seconds) where endpoint?.paid == true:
            return error(.actionInProgress, id, retryAfter: seconds)
        case .normal, .slow, .trickle, .expiredToken, .forbidden, .answerLost, .connectionLost, .attestationRejected,
            .actionInProgress:
            break
        }

        let answer = route(request, body: body, endpoint: endpoint, id: id, refuseNextToken: mode == .expiredToken)
        if mode == .answerLost { return .fail(.timedOut, delay: .milliseconds(80)) }
        if mode == .connectionLost { return .fail(.networkConnectionLost, delay: .milliseconds(80)) }
        if mode == .trickle, case .respond(let status, let headers, let body, _) = answer {
            return .trickle(status: status, headers: headers, body: body)
        }
        if case .slow(let seconds) = mode, case .respond(let status, let headers, let body, _) = answer {
            return .respond(status: status, headers: headers, body: body, delay: .seconds(seconds))
        }
        return answer
    }

    private func route(
        _ request: URLRequest, body: Data?, endpoint: APIV1.Endpoint?, id: String, refuseNextToken: Bool
    ) -> FakeReply {
        guard let path = request.url?.path() else { return error(.notFound, id) }
        if let match = path.firstMatch(of: /^\/v(\d+)(\/|$)/), let version = Int(match.1), version < APIV1.version {
            return error(.apiVersionRetired, id)
        }
        guard let endpoint else {
            let known = APIV1.endpoints.filter { $0.path == path }
            return known.isEmpty
                ? error(.notFound, id)
                : error(.methodNotAllowed, id, headers: ["Allow": known.map(\.method).joined(separator: ", ")])
        }
        if endpoint == APIV1.health {
            return encode(200, APIV1.Health(status: "ok", apiVersion: APIV1.version), id)
        }
        if endpoint == APIV1.deletionStatus {
            return routeDeletionStatus(request, body: body, id: id)
        }

        // The token.
        guard let header = request.value(forHTTPHeaderField: "Authorization"), header.hasPrefix("Bearer "),
            case let token = String(header.dropFirst("Bearer ".count)), let parsed = FakeToken.parse(token)
        else { return error(.unauthenticated, id) }
        let refused = state.withLock { state -> Bool in
            if refuseNextToken { state.refusedTokens.insert(token) }
            return state.refusedTokens.contains(token)
        }
        if refused || parsed.expiresAt <= now() { return error(.tokenExpired, id) }
        // 24c: a deleted sign-in account's tokens stop working, as Clerk's do.
        if isDeletedSubject(parsed.subject) { return error(.unauthenticated, id) }
        if endpoint == APIV1.deleteAccount {
            return routeDeleteAccount(request, body: body, subject: parsed.subject, id: id)
        }
        if isDeleting(parsed.subject) { return error(.forbidden, id, message: "This account is being deleted.") }

        switch endpoint {
        case APIV1.createSession:
            if let problem = checkSessionBody(request, body) { return problem(id) }
            let (user, isNew) = state.withLock { state -> (APIV1.User, Bool) in
                if let existing = state.principals[parsed.subject] {
                    return (APIV1.User(id: existing.id, createdAt: existing.createdAt), false)
                }
                let created = (id: "usr_" + FakeToken.randomHex(16), createdAt: Self.millisecondPrecision(now()))
                state.principals[parsed.subject] = created
                return (APIV1.User(id: created.id, createdAt: created.createdAt), true)
            }
            return encode(200, APIV1.SessionResponse(user: user, newAccount: isNew), id)
        case APIV1.me:
            guard let existing = state.withLock({ $0.principals[parsed.subject] }) else {
                return error(.notRegistered, id)
            }
            return encode(200, APIV1.Me(user: APIV1.User(id: existing.id, createdAt: existing.createdAt)), id)
        case APIV1.sendFeedback:
            guard state.withLock({ $0.principals[parsed.subject] }) != nil else { return error(.notRegistered, id) }
            return routeFeedback(request, body: body, subject: parsed.subject, id: id)
        default:
            guard state.withLock({ $0.principals[parsed.subject] }) != nil else { return error(.notRegistered, id) }
            return routeLimits(request, body: body, endpoint: endpoint, subject: parsed.subject, id: id)
        }
    }

    /// The contract's SessionRequest checks, the way the real gateway makes them.
    private func checkSessionBody(_ request: URLRequest, _ body: Data?) -> ((String) -> FakeReply)? {
        let type = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard type.lowercased().hasPrefix("application/json") else { return { self.error(.unsupportedMediaType, $0) } }
        guard let body, body.count <= APIV1.maxBodyBytes else { return { self.error(.payloadTooLarge, $0) } }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return { self.error(.invalidRequest, $0, message: "The body isn't valid JSON.") }
        }
        if let unknown = object.keys.sorted().first(where: { !["platform", "appVersion"].contains($0) }) {
            return { self.error(.invalidRequest, $0, message: "Unknown field: \(unknown).") }
        }
        guard object["platform"] as? String == "ios",
            let version = object["appVersion"] as? String,
            version.wholeMatch(of: /[0-9]{1,4}(\.[0-9]{1,4}){1,2}/) != nil
        else { return { self.error(.invalidRequest, $0) } }
        return nil
    }

    // MARK: Building answers

    func encode(_ status: Int, _ value: some Encodable, _ id: String) -> FakeReply {
        json(status, (try? APIV1.encoder().encode(value)) ?? Data(), id)
    }

    func json(_ status: Int, _ body: Data, _ id: String, headers: [String: String] = [:]) -> FakeReply {
        var all = headers
        all["Content-Type"] = "application/json"
        all["X-Request-Id"] = id
        all["Cache-Control"] = "no-store"
        return .respond(status: status, headers: all, body: body, delay: .milliseconds(80))
    }

    func error(
        _ code: APIV1.ErrorCode, _ id: String, message: String? = nil, retryAfter: Int? = nil,
        headers: [String: String] = [:], category: String? = nil, resetAt: Date? = nil, feature: String? = nil
    ) -> FakeReply {
        var headers = headers
        if let retryAfter { headers["Retry-After"] = String(retryAfter) }
        if code.status == 401 { headers["WWW-Authenticate"] = "Bearer" }
        let body = APIV1.ErrorEnvelope(
            error: .init(
                code: code.rawValue, message: message ?? "Fake backend: \(code.rawValue).", requestId: id,
                retryAfterSeconds: retryAfter, category: category, resetAt: resetAt.map(APIV1.formatDate),
                feature: feature))
        return json(code.status, (try? APIV1.encoder().encode(body)) ?? Data(), id, headers: headers)
    }

    static func millisecondPrecision(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }
}
