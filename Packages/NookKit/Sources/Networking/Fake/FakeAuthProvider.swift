import Foundation
import Models

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
    /// A pretend sign-in for package tests that aren't about sign-in: a Sign in with Apple that
    /// always succeeds (unless told otherwise) and short-lived tokens (60 seconds by default),
    /// with no sign-in routes involved. The app's fakes use the real client, `BetterAuthProvider`,
    /// against the fake backend's sign-in routes instead. Nothing is stored.
    public actor FakeAuthProvider: AuthProvider {
        public nonisolated let kind = AuthProviderKind.fake

        private let lifetime: TimeInterval
        private let now: @Sendable () -> Date
        private var subject: String?
        private var current: AuthToken?
        private var nextSignInError: AuthError?
        /// How many tokens it has handed out, for tests and the debug screen.
        public private(set) var tokensIssued = 0

        /// - Parameters:
        ///   - lifetime: how long each token lasts.
        ///   - subject: the pretend Apple user, or a random one at each sign-in.
        public init(
            lifetime: TimeInterval = 60, subject: String? = nil, now: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.lifetime = lifetime
            self.now = now
            self.fixedSubject = subject
        }

        private let fixedSubject: String?

        /// Makes the next sign-in fail, for tests and the debug screen. `nil` lets it succeed.
        public func failNextSignIn(with error: AuthError?) {
            nextSignInError = error
        }

        public func isSignedIn() async -> Bool {
            subject != nil
        }

        public func signInWithApple() async throws(AuthError) {
            if let error = nextSignInError {
                nextSignInError = nil
                throw error
            }
            subject = fixedSubject ?? "fake_apple_\(FakeToken.randomHex(6))"
            current = nil
        }

        public func signOut() async {
            subject = nil
            current = nil
        }

        /// The pretend Apple sheet once more. `failNextSignIn` makes it fail too (`cancelled` for a
        /// closed sheet). The code is random and means nothing outside the fake backend.
        public func reauthenticateForDeletion() async throws(AuthError) -> String {
            if let error = nextSignInError {
                nextSignInError = nil
                throw error
            }
            guard subject != nil else { throw .signedOut }
            return "fake-apple-code-" + FakeToken.randomHex(8)
        }

        public func token(forceRefresh: Bool) async throws(AuthError) -> AuthToken {
            guard let subject else { throw .signedOut }
            // Reuse a token with more than 10 seconds left, unless told not to.
            if !forceRefresh, let current, current.expiresAt.timeIntervalSince(now()) > 10 {
                return current
            }
            let expiresAt = now().addingTimeInterval(lifetime)
            let token = AuthToken(value: FakeToken.make(subject: subject, expiresAt: expiresAt), expiresAt: expiresAt)
            current = token
            tokensIssued += 1
            return token
        }
    }
#endif
