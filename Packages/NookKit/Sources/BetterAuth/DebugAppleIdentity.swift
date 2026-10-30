import Foundation
import Models
import Networking

// Debug builds only: stand-ins for Apple's sheet. A Release build signs in with Apple only.
#if DEBUG
    /// Apple's sheet for the in-process fake backend: no sheet at all, and an identity token the
    /// fake's sign-in route accepts (`FakeAppleToken`). One pretend Apple user per install run, so
    /// signing out and in again lands on the same account, as with a real Apple ID.
    public struct FakeAppleIdentity: AppleIdentitySource {
        let subject: String

        public init(subject: String = "fake_apple_" + SignInNonce.make().prefix(12)) {
            self.subject = subject
        }

        public func identityToken(rawNonce: String) async throws(AuthError) -> String {
            FakeAppleToken.make(subject: subject, rawNonce: rawNonce, expiresAt: Date().addingTimeInterval(600))
        }

        public func authorizationCode() async throws(AuthError) -> String {
            "fake-apple-code-" + SignInNonce.make().prefix(16)
        }
    }

    /// Apple's sheet for a local Convex backend (BA4 checkpoint): identity tokens from the backend
    /// repo's fake Apple issuer (`tests/support/fake-apple.mjs`), which the local deployment
    /// trusts in place of Apple when it runs with `NOOK_APPLE_ID_TOKEN_MODE=fake`. Only for an
    /// issuer on this Mac (http://127.0.0.1); anything else is refused.
    public struct LocalFakeAppleIssuer: AppleIdentitySource {
        let issuer: URL
        let subject: String
        let session: URLSession

        /// Nil unless `issuer` is a loopback address.
        public init?(issuer: URL, subject: String = "000123." + SignInNonce.make().prefix(32) + ".0042") {
            guard issuer.scheme == "http", issuer.host() == "127.0.0.1", issuer.port != nil else { return nil }
            self.issuer = issuer
            self.subject = subject
            self.session = URLSession(configuration: .ephemeral)
        }

        public func identityToken(rawNonce: String) async throws(AuthError) -> String {
            var request = URLRequest(url: issuer.appending(path: "/test/mint"))
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["sub": subject, "nonce": rawNonce])
            guard let (data, _) = try? await session.data(for: request),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let token = object["token"] as? String
            else { throw .offline }
            return token
        }

        /// The local backend's Apple revocation runs as a mock; any well-formed code will do.
        public func authorizationCode() async throws(AuthError) -> String {
            "local-fake-apple-code-" + SignInNonce.make().prefix(16)
        }
    }
#endif
