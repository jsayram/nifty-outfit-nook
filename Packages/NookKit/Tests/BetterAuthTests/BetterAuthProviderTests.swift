import Foundation
import Models
import Testing

@testable import BetterAuth
@testable import Networking

/// Apple's sheet for tests: the fake backend's tokens, with a way to make the next answer fail and
/// a record of the nonce it was asked for.
final class TestAppleIdentity: AppleIdentitySource, @unchecked Sendable {
    let subject: String
    private let lock = NSLock()
    private var nextError: AuthError?
    private(set) var nonces: [String] = []

    init(subject: String = "apple_lily") {
        self.subject = subject
    }

    func failNext(with error: AuthError) {
        lock.withLock { nextError = error }
    }

    private func takeError() -> AuthError? {
        lock.withLock {
            defer { nextError = nil }
            return nextError
        }
    }

    func identityToken(rawNonce: String) async throws(AuthError) -> String {
        if let error = takeError() { throw error }
        lock.withLock { nonces.append(rawNonce) }
        return FakeAppleToken.make(subject: subject, rawNonce: rawNonce, expiresAt: Date().addingTimeInterval(600))
    }

    func authorizationCode() async throws(AuthError) -> String {
        if let error = takeError() { throw error }
        return "fake-apple-code-0123456789"
    }
}

/// A wall clock a test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_793_000_000)

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}

/// The Better Auth client (BA4) against the fake backend's sign-in routes, which follow the
/// contract's signIn section.
@Suite("Better Auth sign-in client")
struct BetterAuthProviderTests {
    let backend = FakeBackend()
    let store = MemorySessionStore()
    let apple = TestAppleIdentity()
    let session = APIClient.makeSession(
        policy: RetryPolicy(requestTimeout: .seconds(2)), protocolClasses: [FakeBackendURLProtocol.self])
    let auth: BetterAuthProvider

    init() {
        auth = BetterAuthProvider(
            baseURL: backend.baseURL, session: session, store: store, apple: apple,
            policy: RetryPolicy(baseDelay: .milliseconds(10), requestTimeout: .seconds(2)))
    }

    func account() -> GatewayAccountService {
        let client = APIClient(
            baseURL: backend.baseURL, session: session, auth: auth,
            policy: RetryPolicy(baseDelay: .milliseconds(10), requestTimeout: .seconds(2)))
        return GatewayAccountService(
            auth: auth, client: client, appVersion: "0.1.0", purchaseToken: PurchaseAccountToken())
    }

    @Test func signingInKeepsTheSessionFromTheHeaderOnly() async throws {
        #expect(await !auth.isSignedIn())
        try await auth.signInWithApple()
        #expect(await auth.isSignedIn())
        let kept = try #require(store.load())
        #expect(kept.hasPrefix("fakesession_"))
        #expect(backend.sessionCount == 1)
        // A fresh nonce each time: 64 hex characters from 32 random bytes.
        try await auth.signInWithApple()
        #expect(apple.nonces.count == 2)
        #expect(Set(apple.nonces).count == 2)
        #expect(apple.nonces.allSatisfy { $0.wholeMatch(of: /[0-9a-f]{64}/) != nil })
    }

    @Test func theNonceAppleGetsIsTheHashOfTheOneSent() {
        // The test vector everyone uses for SHA-256: "abc".
        #expect(
            SignInNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func aClosedSheetIsCancelledAndKeepsNothing() async {
        apple.failNext(with: .cancelled)
        await #expect(throws: AuthError.cancelled) { try await auth.signInWithApple() }
        #expect(store.load() == nil)
        #expect(backend.requestCount == 0)
    }

    @Test func tokensAreCachedInMemoryAndRefreshedWhenAsked() async throws {
        try await auth.signInWithApple()
        let first = try await auth.token(forceRefresh: false)
        let again = try await auth.token(forceRefresh: false)
        #expect(first == again)
        let refreshed = try await auth.token(forceRefresh: true)
        #expect(refreshed.value != first.value)
        // The fake's tokens aren't JWTs, so their expiry can't be read: the client takes them to be
        // short-lived. (A real one's `exp` is read: LocalBackendTests.)
        #expect(abs(first.expiresAt.timeIntervalSinceNow - BetterAuthProvider.unreadableLifetime) < 5)
    }

    @Test func aTokenAboutToRunOutIsReplacedBeforeUse() async throws {
        let clock = TestClock()
        let auth = BetterAuthProvider(
            baseURL: backend.baseURL, session: session, store: store, apple: apple, now: { clock.now })
        try await auth.signInWithApple()
        let first = try await auth.token(forceRefresh: false)
        clock.advance(BetterAuthProvider.unreadableLifetime - BetterAuthProvider.refreshMargin - 1)
        #expect(try await auth.token(forceRefresh: false) == first)
        clock.advance(2)
        #expect(try await auth.token(forceRefresh: false) != first)
    }

    @Test func callersAtTheSameMomentShareOneTokenRequest() async throws {
        try await auth.signInWithApple()
        let before = backend.requestCount
        async let a = auth.token(forceRefresh: false)
        async let b = auth.token(forceRefresh: false)
        async let c = auth.token(forceRefresh: false)
        let tokens = try await [a, b, c]
        #expect(Set(tokens.map(\.value)).count == 1)
        #expect(backend.requestCount == before + 1)
    }

    @Test func anEndedSessionSignsHerOutAndForgetsIt() async throws {
        try await auth.signInWithApple()
        backend.expireAllSessions()
        await #expect(throws: AuthError.signedOut) { try await auth.token(forceRefresh: true) }
        #expect(store.load() == nil)
        #expect(await !auth.isSignedIn())
    }

    @Test func noSessionMeansSignedOutWithoutAsking() async {
        await #expect(throws: AuthError.signedOut) { try await auth.token(forceRefresh: false) }
        #expect(backend.requestCount == 0)
    }

    @Test func offlineTokenRequestsSayOfflineAndKeepTheSession() async throws {
        try await auth.signInWithApple()
        backend.setMode(.offline)
        await #expect(throws: AuthError.offline) { try await auth.token(forceRefresh: true) }
        #expect(store.load() != nil)
    }

    @Test func aServerErrorOnTheTokenRouteIsRetried() async throws {
        try await auth.signInWithApple()
        backend.setMode(.serverError, times: 1)
        let token = try await auth.token(forceRefresh: true)
        #expect(!token.value.isEmpty)
    }

    @Test func signingOutEndsTheSessionOnTheServerThenHere() async throws {
        try await auth.signInWithApple()
        #expect(backend.sessionCount == 1)
        await auth.signOut()
        #expect(backend.sessionCount == 0)
        #expect(store.load() == nil)
        await #expect(throws: AuthError.signedOut) { try await auth.token(forceRefresh: false) }
    }

    @Test func signingOutOfflineStillForgetsTheSession() async throws {
        try await auth.signInWithApple()
        backend.setMode(.offline)
        await auth.signOut()
        #expect(store.load() == nil)
        #expect(await !auth.isSignedIn())
    }

    @Test func reauthenticationGoesStraightToApple() async throws {
        await #expect(throws: AuthError.signedOut) { try await auth.reauthenticateForDeletion() }
        try await auth.signInWithApple()
        let before = backend.requestCount
        #expect(try await auth.reauthenticateForDeletion().hasPrefix("fake-apple-code-"))
        #expect(backend.requestCount == before)
        apple.failNext(with: .cancelled)
        await #expect(throws: AuthError.cancelled) { try await auth.reauthenticateForDeletion() }
    }

    // MARK: Through the account service, as the app uses it

    @Test func signInWhoAmIAndAnExpiredTokenRefreshed() async throws {
        let account = account()
        let user = try await account.signIn()
        #expect(user.id.hasPrefix("usr_"))
        #expect(try await account.whoAmI() == user)
        // A token that expired on the way: the client gets a fresh one and the call works.
        backend.setMode(.expiredToken, times: 1)
        #expect(try await account.whoAmI() == user)
        await account.signOut()
        #expect(await !account.isSignedIn())
        await #expect(throws: AccountProblem.signedOut) { try await account.whoAmI() }
    }

    @Test func deletingTheAccountEndsTheSessionAndTheSameAppleIDStartsAgain() async throws {
        let account = account()
        let user = try await account.signIn()
        let deletion = try await account.deleteAccount()
        #expect(deletion.isComplete)
        // The Better Auth user went with its sessions: the next token request is refused.
        #expect(backend.sessionCount == 0)
        await account.forgetAccountOnThisDevice()
        #expect(store.load() == nil)
        let again = try await account.signIn()
        #expect(again.id != user.id)
    }

    // MARK: The fake's sign-in routes refuse what the backend refuses

    func post(_ path: String, _ body: String?, contentType: String? = "application/json", bearer: String? = nil)
        async throws -> (Int, [String: String], Data)
    {
        var request = URLRequest(url: backend.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = body.map { Data($0.utf8) }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        let headers = http.allHeaderFields.reduce(into: [String: String]()) {
            $0[String(describing: $1.key).lowercased()] = String(describing: $1.value)
        }
        return (http.statusCode, headers, data)
    }

    func errorCode(_ data: Data) -> String? {
        (try? JSONDecoder().decode(APIV1.ErrorEnvelope.self, from: data))?.error.code
    }

    @Test func theFakeRefusesWhatTheContractRefuses() async throws {
        let nonce = String(repeating: "a", count: 64)
        let token = FakeAppleToken.make(
            subject: "apple_lily", rawNonce: nonce, expiresAt: Date().addingTimeInterval(60))
        func body(_ idToken: String) -> String { #"{"provider":"apple","idToken":{\#(idToken)}}"# }
        let good = body(#""token":"\#(token)","nonce":"\#(nonce)""#)

        let (status, headers, _) = try await post("/api/auth/sign-in/social", good)
        #expect(status == 200)
        #expect(headers[APIV1.SignIn.sessionHeader]?.hasPrefix("fakesession_") == true)

        // The contract's invalid examples.
        let noNonce = #"{"provider":"apple","idToken":{"token":"\#(token)"}}"#
        #expect(try await errorCode(post("/api/auth/sign-in/social", noNonce).2) == "invalid_request")
        let withName = body(#""token":"\#(token)","nonce":"\#(nonce)","user":{"name":{"firstName":"Lily"}}"#)
        #expect(try await errorCode(post("/api/auth/sign-in/social", withName).2) == "invalid_request")
        // A token for another nonce, or one that's expired: Apple's token doesn't verify.
        let otherNonce = body(#""token":"\#(token)","nonce":"\#(String(repeating: "b", count: 64))""#)
        let (refused, _, refusedBody) = try await post("/api/auth/sign-in/social", otherNonce)
        #expect(refused == 401)
        #expect(errorCode(refusedBody) == "unauthenticated")
        let expired = FakeAppleToken.make(subject: "a", rawNonce: nonce, expiresAt: Date().addingTimeInterval(-1))
        let expiredBody = #"{"provider":"apple","idToken":{"token":"\#(expired)","nonce":"\#(nonce)"}}"#
        #expect(try await post("/api/auth/sign-in/social", expiredBody).0 == 401)
        #expect(try await post("/api/auth/sign-in/social", good, contentType: nil).0 == 415)
        // Every other path under /api/auth, and the right path with the wrong method, is not_found.
        for path in ["/api/auth/sign-up/email", "/api/auth/get-session", "/api/auth/convex/jwks"] {
            let (code, _, body) = try await post(path, "{}")
            #expect(code == 404, "\(path)")
            #expect(errorCode(body) == "not_found")
        }
        // Sign-out needs a session it knows.
        #expect(try await post("/api/auth/sign-out", nil, contentType: nil, bearer: "nope").0 == 401)
    }
}
