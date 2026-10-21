import Foundation
import Models
import Synchronization
import Testing

@testable import Networking

/// The network client and account service against the misbehaving fake backend: every mode the
/// real backend or the network can show, and what the app makes of it.
@Suite("Gateway client")
struct GatewayClientTests {
    /// Records waits instead of sleeping, so retry tests don't take real time.
    final class Recorder: Sendable {
        private let state = Mutex<(waits: [Duration], events: [APIEvent])>(([], []))
        var waits: [Duration] { state.withLock { $0.waits } }
        var events: [APIEvent] { state.withLock { $0.events } }
        func wait(_ duration: Duration) { state.withLock { $0.waits.append(duration) } }
        func record(_ event: APIEvent) { state.withLock { $0.events.append(event) } }
    }

    let backend = FakeBackend()
    let auth = FakeAuthProvider(subject: "lily")
    let recorder = Recorder()

    func service(policy: RetryPolicy = .init(requestTimeout: .seconds(5)), realSleep: Bool = false)
        -> GatewayAccountService
    {
        let recorder = recorder
        let client = APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth, policy: policy,
            sleep: { duration in
                recorder.wait(duration)
                if realSleep { try await Task.sleep(for: duration) } else { try Task.checkCancellation() }
            },
            onEvent: { recorder.record($0) })
        return GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0")
    }

    func expectProblem(_ expected: AccountProblem, _ call: () async throws(AccountProblem) -> AccountUser) async {
        do {
            _ = try await call()
            Issue.record("Expected \(expected), got a user")
        } catch {
            #expect(error == expected)
        }
    }

    // MARK: The happy path

    @Test func signInRegistersTheSessionAndWhoAmIReturnsTheSameAccount() async throws {
        let account = service()
        let signedIn = try await account.signIn()
        #expect(await account.isSignedIn())
        let me = try await account.whoAmI()
        #expect(me == signedIn)
        #expect(backend.accountCount == 1)
        // Signing in again keeps the same account.
        #expect(try await account.signIn() == signedIn)
        #expect(backend.accountCount == 1)
    }

    @Test func whoAmIRegistersASessionThatWasNeverRegistered() async throws {
        try await auth.signInWithApple()
        let me = try await service().whoAmI()
        #expect(me.id.hasPrefix("usr_"))
        #expect(backend.requestCount == 2)  // GET /v1/me (not_registered), then POST /v1/session
    }

    @Test func signedOutNeverReachesTheBackend() async {
        await expectProblem(.signedOut) { () async throws(AccountProblem) in try await service().whoAmI() }
        #expect(backend.requestCount == 0)
    }

    @Test func cancellingAppleSignInIsCancelledNotAnError() async {
        await auth.failNextSignIn(with: .cancelled)
        await expectProblem(.cancelled) { () async throws(AccountProblem) in try await service().signIn() }
        #expect(backend.requestCount == 0)
    }

    @Test func signOutEndsTheSession() async throws {
        let account = service()
        _ = try await account.signIn()
        await account.signOut()
        #expect(!(await account.isSignedIn()))
        await expectProblem(.signedOut) { () async throws(AccountProblem) in try await account.whoAmI() }
    }

    // MARK: Tokens

    @Test func anExpiredTokenIsRefreshedOnceAndTheCallSucceeds() async throws {
        let account = service()
        _ = try await account.signIn()
        let tokensBefore = await auth.tokensIssued
        backend.setMode(.expiredToken, times: 1)
        let me = try await account.whoAmI()
        #expect(me.id.hasPrefix("usr_"))
        #expect(await auth.tokensIssued == tokensBefore + 1)
        #expect(recorder.events.contains(.refreshedToken(endpoint: "me")))
        #expect(recorder.events.contains(.received(endpoint: "me", status: 401, code: "token_expired")))
    }

    @Test func aSecondRefusalMeansSignedOut() async throws {
        let account = service()
        _ = try await account.signIn()
        backend.setMode(.expiredToken)  // refuses every token it sees
        await expectProblem(.signedOut) { () async throws(AccountProblem) in try await account.whoAmI() }
        #expect(recorder.events.filter { $0 == .refreshedToken(endpoint: "me") }.count == 1)
    }

    @Test func aCachedTokenIsReusedUntilItIsAboutToExpire() async throws {
        let account = service()
        _ = try await account.signIn()
        _ = try await account.whoAmI()
        _ = try await account.whoAmI()
        #expect(await auth.tokensIssued == 1)
    }

    // MARK: Server answers

    @Test func forbiddenIsNotRetried() async throws {
        let account = service()
        _ = try await account.signIn()
        let before = backend.requestCount
        backend.setMode(.forbidden)
        await expectProblem(.forbidden) { () async throws(AccountProblem) in try await account.whoAmI() }
        #expect(backend.requestCount == before + 1)
    }

    @Test func aLongRetryAfterIsHandedToTheScreen() async throws {
        let account = service()
        _ = try await account.signIn()
        let before = backend.requestCount
        backend.setMode(.rateLimited(retryAfterSeconds: 30))
        await expectProblem(.rateLimited(retryAfterSeconds: 30)) { () async throws(AccountProblem) in
            try await account.whoAmI()
        }
        #expect(backend.requestCount == before + 1)
        #expect(recorder.waits.isEmpty)
    }

    @Test func aShortRetryAfterIsWaitedOut() async throws {
        let account = service()
        _ = try await account.signIn()
        backend.setMode(.rateLimited(retryAfterSeconds: 1), times: 1)
        _ = try await account.whoAmI()
        #expect(recorder.waits == [.seconds(1)])
    }

    @Test func serverErrorsAreRetriedWithBackoffThenReported() async throws {
        let account = service()
        _ = try await account.signIn()
        let before = backend.requestCount
        backend.setMode(.serverError)
        await expectProblem(.serverError) { () async throws(AccountProblem) in try await account.whoAmI() }
        #expect(backend.requestCount == before + 3)
        #expect(recorder.waits.count == 2)
        #expect(recorder.waits[0] >= .milliseconds(400) && recorder.waits[0] <= .milliseconds(500))
        #expect(recorder.waits[1] >= .milliseconds(800) && recorder.waits[1] <= .milliseconds(1000))
    }

    @Test func oneServerErrorRecovers() async throws {
        let account = service()
        _ = try await account.signIn()
        backend.setMode(.serverError, times: 1)
        _ = try await account.whoAmI()
        #expect(recorder.waits.count == 1)
    }

    @Test func unavailableCarriesRetryAfter() async throws {
        let account = service()
        _ = try await account.signIn()
        backend.setMode(.unavailable(retryAfterSeconds: 120))
        await expectProblem(.unavailable(retryAfterSeconds: 120)) { () async throws(AccountProblem) in
            try await account.whoAmI()
        }
    }

    @Test func malformedJSONIsAnInvalidResponse() async throws {
        let account = service()
        _ = try await account.signIn()
        backend.setMode(.malformedJSON)
        await expectProblem(.invalidResponse) { () async throws(AccountProblem) in try await account.whoAmI() }
    }

    // MARK: The network

    @Test func offlineFailsAtOnceWithoutRetrying() async throws {
        let account = service()
        try await auth.signInWithApple()
        backend.setMode(.offline)
        await expectProblem(.offline) { () async throws(AccountProblem) in try await account.whoAmI() }
        #expect(backend.requestCount == 1)
        #expect(recorder.waits.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func aBackendThatNeverAnswersTimesOutAfterBoundedTries() async throws {
        let policy = RetryPolicy(maxAttempts: 2, requestTimeout: .milliseconds(500))
        let account = service(policy: policy)
        try await auth.signInWithApple()
        backend.setMode(.timeout)
        let started = ContinuousClock.now
        await expectProblem(.timedOut) { () async throws(AccountProblem) in try await account.whoAmI() }
        #expect(backend.requestCount == 2)
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func aSlowBackendStillAnswers() async throws {
        let account = service()
        _ = try await account.signIn()
        backend.setMode(.slow(seconds: 0.3))
        let started = ContinuousClock.now
        _ = try await account.whoAmI()
        #expect(ContinuousClock.now - started >= .milliseconds(300))
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingACallStopsIt() async throws {
        let account = service()
        _ = try await account.signIn()
        backend.setMode(.slow(seconds: 20))
        let call = Task { () async -> AccountProblem? in
            do {
                _ = try await account.whoAmI()
                return nil
            } catch {
                return error as? AccountProblem
            }
        }
        try await Task.sleep(for: .milliseconds(150))
        call.cancel()
        let problem = await call.value
        #expect(problem == .cancelled)
    }

    // MARK: Pieces

    @Test func urlErrorsMapToFailures() {
        #expect(APIClient.failure(for: URLError(.notConnectedToInternet)) == .offline)
        #expect(APIClient.failure(for: URLError(.networkConnectionLost)) == .offline)
        #expect(APIClient.failure(for: URLError(.timedOut)) == .timedOut)
        #expect(APIClient.failure(for: URLError(.cancelled)) == .cancelled)
        #expect(APIClient.failure(for: URLError(.cannotParseResponse)) == .invalidResponse)
    }

    @Test func eventsNeverHoldTokens() async throws {
        let account = service()
        _ = try await account.signIn()
        backend.setMode(.expiredToken, times: 1)
        _ = try await account.whoAmI()
        let token = try await auth.token(forceRefresh: false).value
        #expect(!recorder.events.map { String(describing: $0) }.joined().contains(token))
        #expect(!recorder.events.map { String(describing: $0) }.joined().contains("fake1."))
    }
}
