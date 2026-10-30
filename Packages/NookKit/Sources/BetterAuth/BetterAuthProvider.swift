import Foundation
import Models
import Networking

/// Sign in with Apple through Better Auth inside our Convex deployment (BA4, closet
/// SWIFT_BUILD_PLAN "Sign-in on Better Auth"), behind the same `AuthProvider` the screens already
/// use. Better Auth ships no Swift client, so this speaks the contract's `signIn` routes itself.
///
/// - Sign in: Apple's identity token for a fresh nonce goes to `POST /api/auth/sign-in/social`,
///   and the session from the `set-auth-token` header goes into the `SessionStore` (the Keychain
///   in the app). Nothing else from the answer is kept.
/// - Tokens: `GET /api/auth/convex/token` with the session as bearer gives the 5-minute Convex
///   token /v1 takes. It stays in memory only, and a new one is fetched before it runs out, or
///   when the backend refused the last one. A 401 there means the session has ended: it's
///   deleted, and she's signed out.
/// - Sign out ends the session on the server, then deletes it here, even when the server can't
///   be reached.
/// - Every request has a time limit, and only the token request, which is safe to repeat, is
///   retried. Nothing here logs a token.
public actor BetterAuthProvider: AuthProvider {
    public nonisolated let kind = AuthProviderKind.betterAuth

    private let baseURL: URL
    private let session: URLSession
    private let store: any SessionStore
    private let apple: any AppleIdentitySource
    private let policy: RetryPolicy
    private let now: @Sendable () -> Date
    private let onEvent: @Sendable (APIEvent) -> Void

    /// The Convex token, in memory only.
    private var current: AuthToken?
    /// A token request already on its way, so callers at the same moment share it.
    private var pending: Task<AuthToken, any Error>?

    /// A Convex token with less than this left is replaced before it's used.
    static let refreshMargin: TimeInterval = 30
    /// How long a Convex token is taken to last when its expiry can't be read.
    static let unreadableLifetime: TimeInterval = 60

    /// - Parameters:
    ///   - baseURL: the deployment's `.convex.site` address, the same one /v1 uses.
    ///   - session: an ephemeral session with no cookies (`APIClient.makeSession`).
    ///   - onEvent: each request and answer, for the debug gateway screen. Never a token or a body.
    public init(
        baseURL: URL, session: URLSession, store: any SessionStore, apple: any AppleIdentitySource,
        policy: RetryPolicy = .standard, now: @escaping @Sendable () -> Date = { Date() },
        onEvent: @escaping @Sendable (APIEvent) -> Void = { _ in }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.store = store
        self.apple = apple
        self.policy = policy
        self.now = now
        self.onEvent = onEvent
    }

    public func isSignedIn() async -> Bool {
        store.load() != nil
    }

    public func signInWithApple() async throws(AuthError) {
        let nonce = SignInNonce.make()
        let identityToken = try await apple.identityToken(rawNonce: nonce)
        let body: Data
        do {
            body = try APIV1.encoder().encode(
                APIV1.SignIn.AppleSignInRequest(identityToken: identityToken, rawNonce: nonce))
        } catch {
            throw .failed
        }
        // Not retried: Apple's token and its nonce are for one sign-in.
        let (response, _) = try await send(APIV1.SignIn.signInApple, body: body, session: nil)
        guard response.statusCode == 200,
            let issued = response.value(forHTTPHeaderField: APIV1.SignIn.sessionHeader),
            APIV1.SignIn.isPlausibleSession(issued)
        else {
            throw Self.error(forStatus: response.statusCode)
        }
        current = nil
        pending?.cancel()
        pending = nil
        guard store.save(issued) else { throw .failed }
    }

    public func signOut() async {
        current = nil
        pending?.cancel()
        pending = nil
        if let existing = store.load() {
            // Best effort: the answer doesn't matter, and offline the session simply ends here.
            _ = try? await send(APIV1.SignIn.signOut, body: nil, session: existing, timeout: .seconds(5))
        }
        store.clear()
    }

    public func reauthenticateForDeletion() async throws(AuthError) -> String {
        guard store.load() != nil else { throw .signedOut }
        return try await apple.authorizationCode()
    }

    public func token(forceRefresh: Bool) async throws(AuthError) -> AuthToken {
        if !forceRefresh, let current, current.expiresAt.timeIntervalSince(now()) > Self.refreshMargin {
            return current
        }
        if forceRefresh { current = nil }
        let task: Task<AuthToken, any Error>
        if let pending, !forceRefresh {
            task = pending
        } else {
            task = Task { try await self.fetchToken() }
            pending = task
        }
        do {
            let token = try await task.value
            if pending == task { pending = nil }
            return token
        } catch {
            if pending == task { pending = nil }
            throw (error as? AuthError) ?? .failed
        }
    }

    // MARK: Requests

    private func fetchToken() async throws(AuthError) -> AuthToken {
        guard let existing = store.load() else { throw .signedOut }
        var attempt = 0
        while true {
            attempt += 1
            let response: HTTPURLResponse
            let data: Data
            do {
                (response, data) = try await send(APIV1.SignIn.convexToken, body: nil, session: existing)
            } catch .failed where attempt < policy.maxAttempts {
                // A timeout or a dropped connection: the request is safe to repeat.
                try await pause(attempt)
                continue
            }
            switch response.statusCode {
            case 200:
                guard let answer = try? JSONDecoder().decode(APIV1.SignIn.ConvexTokenResponse.self, from: data),
                    !answer.token.isEmpty
                else { throw .failed }
                let expiresAt =
                    JWTClaims.expiry(of: answer.token) ?? now().addingTimeInterval(Self.unreadableLifetime)
                let token = AuthToken(value: answer.token, expiresAt: expiresAt)
                // A sign-out while this was on its way wins: no token for a session that's gone.
                guard store.load() == existing else { throw .signedOut }
                current = token
                return token
            case 401:
                // The session has ended (7 days unused, signed out elsewhere, or the account
                // deleted). Forget it here too, unless a new sign-in already replaced it.
                if store.load() == existing { store.clear() }
                current = nil
                throw .signedOut
            case 500..<600 where attempt < policy.maxAttempts:
                try await pause(attempt)
            default:
                throw .failed
            }
        }
    }

    private func pause(_ attempt: Int) async throws(AuthError) {
        let delay = min(policy.baseDelay * (1 << (attempt - 1)), policy.maxDelay)
        do {
            try await Task.sleep(for: delay)
        } catch {
            throw .failed
        }
    }

    /// One try at a sign-in route. Answers with any HTTP status; throws `offline` when there's
    /// no connection and `failed` for a timeout, a dropped connection or anything else.
    private func send(
        _ route: APIV1.SignIn.Route, body: Data?, session bearer: String?, timeout: Duration? = nil
    ) async throws(AuthError) -> (HTTPURLResponse, Data) {
        var request = URLRequest(url: baseURL.appending(path: route.path))
        request.httpMethod = route.method
        request.timeoutInterval = (timeout ?? policy.requestTimeout).seconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        onEvent(.sent(endpoint: route.id, attempt: 1))
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .cannotFindHost,
                .cannotConnectToHost:
                onEvent(.failed(endpoint: route.id, failure: .offline))
                throw .offline
            default:
                onEvent(.failed(endpoint: route.id, failure: error.code == .timedOut ? .timedOut : .offline))
                throw .failed
            }
        } catch {
            throw .failed
        }
        guard let http = response as? HTTPURLResponse else { throw .failed }
        let envelope =
            (200..<300).contains(http.statusCode)
            ? nil : try? JSONDecoder().decode(APIV1.ErrorEnvelope.self, from: data)
        let code = envelope?.error.code
        onEvent(.received(endpoint: route.id, status: http.statusCode, code: code))
        return (http, data)
    }

    static func error(forStatus status: Int) -> AuthError {
        switch status {
        case 401: .signedOut
        default: .failed
        }
    }
}

extension Duration {
    fileprivate var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
