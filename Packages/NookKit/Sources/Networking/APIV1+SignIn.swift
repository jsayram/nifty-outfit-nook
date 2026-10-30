import Foundation

extension APIV1 {
    /// Sign in with Apple through Better Auth (BA4), the contract's `signIn` section. The routes
    /// live in the same deployment as /v1, on the same host, under /api/auth. Four routes only; the
    /// backend answers every other path there with not_found.
    ///
    /// - Sign-in posts Apple's identity token and the raw nonce whose SHA-256 went to Apple. The
    ///   session is the `set-auth-token` response header, and nothing else from the answer is kept.
    /// - The session goes as `Authorization: Bearer` to the token and sign-out routes only. /v1
    ///   gets the 5-minute Convex token from the token route instead.
    public enum SignIn {
        public static let basePath = "/api/auth"
        /// The response header that carries the session after a sign-in.
        public static let sessionHeader = "set-auth-token"

        /// One route: its method, path, whether it takes the session as its bearer token, and the
        /// largest body it accepts (nil when it takes none).
        public struct Route: Sendable, Hashable {
            public var id: String
            public var method: String
            public var path: String
            public var requiresSession: Bool
            public var maxBodyBytes: Int?
        }

        public static let signInApple = Route(
            id: "signInApple", method: "POST", path: "/api/auth/sign-in/social", requiresSession: false,
            maxBodyBytes: 8_192)
        public static let convexToken = Route(
            id: "convexToken", method: "GET", path: "/api/auth/convex/token", requiresSession: true)
        public static let signOut = Route(
            id: "signOut", method: "POST", path: "/api/auth/sign-out", requiresSession: true)
        /// For Convex itself. The app never calls it; it's here so the contract test sees all four.
        public static let convexJwks = Route(
            id: "convexJwks", method: "GET", path: "/api/auth/convex/jwks", requiresSession: false)

        public static let routes = [signInApple, convexToken, signOut, convexJwks]

        public struct AppleSignInRequest: Codable, Sendable, Equatable {
            public struct IdToken: Codable, Sendable, Equatable {
                /// Apple's identity token, as Apple returned it.
                public var token: String
                /// The raw nonce. Apple got its SHA-256, in lowercase hex.
                public var nonce: String
            }

            public var provider: String
            public var idToken: IdToken

            public init(identityToken: String, rawNonce: String) {
                provider = "apple"
                idToken = IdToken(token: identityToken, nonce: rawNonce)
            }
        }

        /// The sign-in answer's body. The app reads none of it (the session is the header); it's
        /// decoded only by the contract tests and the fake backend.
        public struct AppleSignInResponse: Codable, Sendable, Equatable {
            public struct User: Codable, Sendable, Equatable {
                public var id: String
            }

            public var redirect: Bool?
            public var token: String
            public var user: User
        }

        public struct ConvexTokenResponse: Codable, Sendable, Equatable {
            public var token: String
        }

        public struct SignOutResponse: Codable, Sendable, Equatable {
            public var success: Bool
        }

        /// What a session from `set-auth-token` may look like: Better Auth's opaque token, which
        /// is URL-safe text. Anything else is treated as no session at all.
        public static func isPlausibleSession(_ value: String) -> Bool {
            value.wholeMatch(of: /[A-Za-z0-9._~+\/=-]{16,256}/) != nil
        }
    }
}
