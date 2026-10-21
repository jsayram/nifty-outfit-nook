import Foundation

// Sign-in and the backend account (Phase 24a). Her closet never depends on any of this: the local
// stores work signed out, offline, or with the backend down. Only cloud features will need it.

/// A bearer token for the backend, and when it stops working.
public struct AuthToken: Sendable, Equatable {
    public var value: String
    public var expiresAt: Date

    public init(value: String, expiresAt: Date) {
        self.value = value
        self.expiresAt = expiresAt
    }
}

/// Why signing in, or getting a token, didn't work.
public enum AuthError: Error, Sendable, Equatable {
    /// She closed the Sign in with Apple sheet.
    case cancelled
    /// No session: never signed in, signed out, or the session ended (Clerk's 7-day limit, D4).
    case signedOut
    /// The sign-in service couldn't be reached.
    case offline
    /// Anything else. Nothing more specific is kept, so no identity details end up in errors.
    case failed
}

/// Which sign-in is running. The fake is the default until a Clerk key is configured.
public enum AuthProviderKind: String, Sendable {
    case fake
    case clerk
}

/// Who signs her in and keeps the token for the backend fresh. `FakeAuthProvider` (Networking)
/// by default; `ClerkAuthProvider` (ClerkAuth) when the app has a Clerk publishable key.
public protocol AuthProvider: Sendable {
    var kind: AuthProviderKind { get }
    func isSignedIn() async -> Bool
    /// Runs Sign in with Apple and starts a session.
    func signInWithApple() async throws(AuthError)
    /// Ends the session on this device. Never fails from her point of view.
    func signOut() async
    /// A token for the backend. A cached one while it has time left; a new one when it's about to
    /// expire, or when `forceRefresh` is set because the backend refused the last one.
    func token(forceRefresh: Bool) async throws(AuthError) -> AuthToken
}

/// Her account on the backend, as the app sees it: a pseudonymous ID, never a name or email.
public struct AccountUser: Sendable, Equatable {
    public var id: String
    public var createdAt: Date

    public init(id: String, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

/// Why an account call didn't work, in the terms a screen needs to explain it.
public enum AccountProblem: Error, Sendable, Equatable {
    /// She closed the Sign in with Apple sheet. Not an error to show.
    case cancelled
    /// Not signed in, or the backend refused a fresh token too.
    case signedOut
    /// No connection.
    case offline
    /// The backend didn't answer in time.
    case timedOut
    /// Too many requests. Try again after this many seconds.
    case rateLimited(retryAfterSeconds: Int)
    /// Signed in, but not allowed.
    case forbidden
    /// Switched off or overloaded. Try again later, after this many seconds when known.
    case unavailable(retryAfterSeconds: Int?)
    /// The backend failed, even after retrying.
    case serverError
    /// This version of the app is too old for the backend.
    case updateRequired
    /// The backend's answer didn't match the contract.
    case invalidResponse
    /// The backend rejected the request as malformed: a bug in the app, never her fault.
    case rejected
}

/// Sign in, the session, and who am I (Phase 24a). Later phases add deletion (24c), feedback (24d)
/// and styling (27a) as their own services.
public protocol AccountService: Sendable {
    var providerKind: AuthProviderKind { get }
    func isSignedIn() async -> Bool
    /// Signs in with Apple, then registers the session with the backend.
    func signIn() async throws(AccountProblem) -> AccountUser
    /// Asks the backend who the current token belongs to.
    func whoAmI() async throws(AccountProblem) -> AccountUser
    func signOut() async
}

/// No account service: every call says signed out. What screens get when nothing configured one.
public struct UnavailableAccountService: AccountService {
    public init() {}
    public var providerKind: AuthProviderKind { .fake }
    public func isSignedIn() async -> Bool { false }
    public func signIn() async throws(AccountProblem) -> AccountUser { throw .signedOut }
    public func whoAmI() async throws(AccountProblem) -> AccountUser { throw .signedOut }
    public func signOut() async {}
}
