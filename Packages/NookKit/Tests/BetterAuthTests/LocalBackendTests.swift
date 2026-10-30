import Foundation
import Models
import Testing

@testable import BetterAuth
@testable import Networking

/// BA4's checkpoint against a real local Convex backend from the private backend repo, with its
/// fake Apple issuer standing in for Apple. Skipped unless both addresses are given, as
/// `TEST_RUNNER_NOOK_LOCAL_SITE_URL` and `TEST_RUNNER_NOOK_FAKE_APPLE_URL` (loopback only):
///
///     TEST_RUNNER_NOOK_LOCAL_SITE_URL=http://127.0.0.1:<site port> \
///     TEST_RUNNER_NOOK_FAKE_APPLE_URL=http://127.0.0.1:<port> \
///     scripts/test.sh -only-testing:BetterAuthTests/LocalBackendTests
enum LocalBackend {
    static let addresses: (site: URL, apple: URL)? = {
        let environment = ProcessInfo.processInfo.environment
        guard let site = environment["NOOK_LOCAL_SITE_URL"].flatMap(URL.init), site.host() == "127.0.0.1",
            let apple = environment["NOOK_FAKE_APPLE_URL"].flatMap(URL.init), apple.host() == "127.0.0.1"
        else { return nil }
        return (site, apple)
    }()
}

@Suite("Better Auth on a local backend", .enabled(if: LocalBackend.addresses != nil))
struct LocalBackendTests {
    @Test @MainActor func signInWhoAmIRefreshAndSignOut() async throws {
        let (site, issuer) = try #require(LocalBackend.addresses)
        let apple = try #require(LocalFakeAppleIssuer(issuer: issuer))
        let store = MemorySessionStore()
        let services = RealGateway.make(baseURL: site, apple: apple, store: store, appVersion: "0.1.0")
        let account = services.account

        let user = try await account.signIn()
        #expect(user.id.hasPrefix("usr_"))
        let session = try #require(store.load())
        #expect(APIV1.SignIn.isPlausibleSession(session))
        #expect(try await account.whoAmI() == user)

        // A fresh Convex token from the session works too, and is a JWT with an expiry.
        let auth = BetterAuthProvider(
            baseURL: site, session: APIClient.makeSession(), store: store, apple: apple)
        let token = try await auth.token(forceRefresh: true)
        #expect(JWTClaims.expiry(of: token.value) != nil)
        #expect(token.expiresAt.timeIntervalSinceNow <= 5 * 60 + 5)

        // Signing in again with the same Apple ID lands on the same account.
        await account.signOut()
        #expect(store.load() == nil)
        // The old session is over on the server: the token route refuses it.
        _ = store.save(session)
        await #expect(throws: AuthError.signedOut) { try await auth.token(forceRefresh: true) }
        #expect(store.load() == nil)
        #expect(try await account.signIn() == user)
        await account.signOut()
    }
}
