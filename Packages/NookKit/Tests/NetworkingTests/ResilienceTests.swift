import Foundation
import Models
import Network
import Synchronization
import Testing

@testable import Networking

/// Phase 26's checkpoint: every way a call can fail, forced against the fake backend, with what
/// the client does about it (PRD 11.7, SECURITY_STANDARD 4). One test per case in the plan:
/// slow, timeout, offline at the start and in the middle, 401 then a fresh token, 401 and the
/// refresh fails, 429 with Retry-After, 500 and 503 retried and given up on, malformed JSON, and
/// cancellation. `docs/network-resilience.md` has the rules these check.
@Suite("Network resilience")
struct ResilienceTests {
    /// Records waits instead of sleeping, so a retry test doesn't take real time, unless it asks
    /// for real sleeping to exercise cancellation.
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

    func client(
        _ policy: RetryPolicy = RetryPolicy(requestTimeout: .seconds(5)), realSleep: Bool = false,
        auth: (any AuthProvider)? = nil
    ) -> APIClient {
        let recorder = recorder
        return APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth ?? self.auth, policy: policy,
            sleep: { duration in
                recorder.wait(duration)
                if realSleep { try await Task.sleep(for: duration) } else { try Task.checkCancellation() }
            },
            onEvent: { recorder.record($0) })
    }

    /// Signs in and registers the session, so Who am I answers.
    func signedIn(_ client: APIClient) async throws {
        _ = try await GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0").signIn()
    }

    func me(_ client: APIClient) async -> APIFailure? {
        do {
            _ = try await client.send(APIV1.me, as: APIV1.Me.self)
            return nil
        } catch {
            return error
        }
    }

    func paid(_ client: APIClient) async throws -> GatewayPaidActionService {
        let session = AttestationSession(attester: FakeDeviceAttester(), store: MemoryAttestKeyStore(), client: client)
        return GatewayPaidActionService(client: client, attestation: session)
    }

    static let swap = PaidActionRequest.style(mode: .swap, contextRevision: "rev_1")

    // MARK: Timeouts

    @Test func eachEndpointHasItsOwnTiming() {
        let policy = RetryPolicy.standard
        #expect(policy.timing(for: APIV1.me) == EndpointTiming(attemptTimeout: .seconds(10), deadline: .seconds(30)))
        // A paid text request waits for the server's own 30 second deadline, and a little more.
        #expect(policy.timing(for: APIV1.style) == EndpointTiming(attemptTimeout: .seconds(40), deadline: .seconds(45)))
        // A try-on picture gets PRD 9.2.4's proposed aggregate bound, each try being a short call.
        #expect(
            policy.timing(for: APIV1.tryOn) == EndpointTiming(attemptTimeout: .seconds(30), deadline: .seconds(360)))
        #expect(policy.longestDeadline == .seconds(360))
        let session = APIClient.makeSession(policy: policy)
        #expect(session.configuration.timeoutIntervalForResource >= 360)
        #expect(session.configuration.waitsForConnectivity == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func aTryIsCutOffAtItsLimitEvenWhenTheServerIsOnlySlow() async throws {
        let policy = RetryPolicy(maxAttempts: 1, requestTimeout: .milliseconds(300))
        let client = client(policy)
        try await signedIn(client)
        backend.setMode(.slow(seconds: 20))
        let started = ContinuousClock.now
        #expect(await me(client) == .timedOut)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test(.timeLimit(.minutes(1)))
    func aTryIsCutOffAtItsLimitEvenWhenTheServerKeepsTrickling() async throws {
        // One byte every 100 ms is never silent for 300 ms, so only a hard limit ends it. The
        // answer is about 150 bytes, so it would take about 15 seconds on its own.
        let policy = RetryPolicy(maxAttempts: 1, requestTimeout: .milliseconds(300))
        let client = client(policy)
        try await signedIn(client)
        backend.setMode(.trickle)
        let started = ContinuousClock.now
        #expect(await me(client) == .timedOut)
        #expect(ContinuousClock.now - started < .seconds(6))
    }

    @Test func aSlowAnswerWithinTheLimitStillArrives() async throws {
        let client = client()
        try await signedIn(client)
        backend.setMode(.slow(seconds: 0.4))
        let started = ContinuousClock.now
        #expect(await me(client) == nil)
        #expect(ContinuousClock.now - started >= .milliseconds(400))
    }

    @Test(.timeLimit(.minutes(1)))
    func aServerThatNeverAnswersIsTriedAgainOnlyWithinTheDeadline() async throws {
        // Tries of 0.2 s with a deadline of 0.5 s: the third can't finish, so there are fewer
        // tries than `maxAttempts`, and the call ends at the deadline.
        let policy = RetryPolicy(
            maxAttempts: 10, baseDelay: .milliseconds(10), maxDelay: .milliseconds(20),
            requestTimeout: .milliseconds(200), overallDeadline: .milliseconds(500), timingOverrides: [:])
        let client = client(policy, realSleep: true)
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.timeout)
        let started = ContinuousClock.now
        #expect(await me(client) == .timedOut)
        let elapsed = ContinuousClock.now - started
        #expect(elapsed >= .milliseconds(450) && elapsed < .seconds(10))
        let tries = backend.requestCount - before
        #expect(tries >= 2 && tries < 10)
    }

    @Test func aBackoffThatCannotFitTheDeadlineIsNotWaited() async throws {
        let policy = RetryPolicy(
            baseDelay: .seconds(5), maxDelay: .seconds(5), requestTimeout: .seconds(5), overallDeadline: .seconds(2),
            timingOverrides: [:])
        let client = client(policy)
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.serverError)
        #expect(await me(client) == .serverError)
        #expect(backend.requestCount == before + 1)
        #expect(recorder.waits.isEmpty)
    }

    // MARK: Offline

    @Test func offlineAtTheStartFailsAtOnceWithoutRetrying() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.offline)
        #expect(await me(client) == .offline)
        #expect(backend.requestCount == before + 1)
        #expect(recorder.waits.isEmpty)
    }

    @Test func aConnectionLostInTheMiddleIsTriedAgainOnceItIsBack() async throws {
        let client = client()
        try await signedIn(client)
        backend.setMode(.connectionLost, times: 1)
        #expect(await me(client) == nil)
        #expect(recorder.waits.count == 1)
        #expect(recorder.events.contains { if case .retrying(_, _, "connection lost") = $0 { true } else { false } })
    }

    @Test func aConnectionThatStaysLostIsGivenUpOnAfterTheBoundedTries() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.connectionLost)
        #expect(await me(client) == .offline)
        #expect(backend.requestCount == before + 3)
        #expect(recorder.waits.count == 2)
    }

    @Test func aRequestThatIsNotSafeToRepeatIsNotRetriedAfterAConnectionLoss() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.connectionLost)
        do {
            _ = try await client.send(
                APIV1.attestChallenge, body: Optional<APIV1.SessionRequest>.none, as: APIV1.AttestChallenge.self)
            Issue.record("Expected a failure")
        } catch {
            #expect(error == .offline)
        }
        #expect(backend.requestCount == before + 1)
    }

    @Test func aPaidRequestLostInTheMiddleRunsOnceAndIsCountedOnce() async throws {
        let client = client()
        try await signedIn(client)
        let service = try await paid(client)
        // Registers this device's key first, so the lost answer is the paid one.
        _ = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        backend.setMode(.connectionLost, times: 1)
        let receipt = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        // The server did the work before the connection dropped; the retry with the same key
        // got the first answer back.
        #expect(receipt.replayed)
        #expect(receipt.usage.usedToday == 2)
        #expect(backend.paidJobsRun == 2)
    }

    // MARK: 401

    @Test func aRefusedTokenIsRefreshedOnceAndTheCallGoesThrough() async throws {
        let client = client()
        try await signedIn(client)
        let issued = await auth.tokensIssued
        backend.setMode(.expiredToken, times: 1)
        #expect(await me(client) == nil)
        #expect(await auth.tokensIssued == issued + 1)
        #expect(recorder.events.filter { $0 == .refreshedToken(endpoint: "me") }.count == 1)
    }

    @Test func aFreshTokenThatIsRefusedAgainEndsTheSessionGracefully() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.expiredToken)  // refuses every token it sees
        #expect(await me(client) == .signedOut)
        // Two requests only: the first, and the one with a fresh token. Never a third.
        #expect(backend.requestCount == before + 2)
        #expect(await auth.isSignedIn() == false)
        #expect(recorder.events.contains(.sessionEnded(endpoint: "me")))
        // Her next call doesn't reach the backend at all: she is signed out and asked to sign in.
        #expect(await me(client) == .signedOut)
        #expect(backend.requestCount == before + 2)
    }

    /// An auth provider whose refresh fails the way Clerk's can: a token for the first ask, then
    /// an error when the client asks for a fresh one.
    final class RefreshFailsAuth: AuthProvider {
        let inner = FakeAuthProvider(subject: "lily")
        let signOuts = Mutex(0)
        var kind: AuthProviderKind { .fake }
        func isSignedIn() async -> Bool { await inner.isSignedIn() }
        func signInWithApple() async throws(AuthError) { try await inner.signInWithApple() }
        func reauthenticateForDeletion() async throws(AuthError) -> String {
            try await inner.reauthenticateForDeletion()
        }
        func signOut() async {
            signOuts.withLock { $0 += 1 }
            await inner.signOut()
        }
        func token(forceRefresh: Bool) async throws(AuthError) -> AuthToken {
            if forceRefresh { throw .failed }
            return try await inner.token(forceRefresh: false)
        }
    }

    @Test func aRefreshThatFailsEndsTheSessionGracefully() async throws {
        let failing = RefreshFailsAuth()
        let client = client(auth: failing)
        _ = try await GatewayAccountService(auth: failing, client: client, appVersion: "0.1.0").signIn()
        backend.setMode(.expiredToken, times: 1)
        #expect(await me(client) == .signedOut)
        #expect(failing.signOuts.withLock { $0 } == 1)
        #expect(await failing.isSignedIn() == false)
    }

    @Test func aHiccupGettingAFirstTokenDoesNotSignHerOut() async throws {
        final class Hiccup: AuthProvider {
            let inner = FakeAuthProvider(subject: "lily")
            var kind: AuthProviderKind { .fake }
            func isSignedIn() async -> Bool { await inner.isSignedIn() }
            func signInWithApple() async throws(AuthError) { try await inner.signInWithApple() }
            func reauthenticateForDeletion() async throws(AuthError) -> String {
                try await inner.reauthenticateForDeletion()
            }
            func signOut() async { await inner.signOut() }
            func token(forceRefresh: Bool) async throws(AuthError) -> AuthToken { throw .failed }
        }
        let hiccup = Hiccup()
        try await hiccup.signInWithApple()
        let client = client(auth: hiccup)
        #expect(await me(client) == .unavailable(retryAfterSeconds: nil))
        #expect(await hiccup.isSignedIn())
        #expect(backend.requestCount == 0)
    }

    @Test func aPaidRequestKeepsItsKeyThroughATokenRefresh() async throws {
        let client = client()
        try await signedIn(client)
        let service = try await paid(client)
        _ = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        backend.setMode(.expiredToken, times: 1)
        let receipt = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        #expect(!receipt.replayed)
        #expect(backend.paidJobsRun == 2)
    }

    // MARK: 4xx

    @Test func otherClientErrorsAreNeverRetried() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        let unknown = APIV1.Endpoint(
            id: "nope", method: "GET", path: "/v1/nope", requiresAuth: true, idempotent: true)
        do {
            _ = try await client.send(unknown, as: APIV1.Me.self)
            Issue.record("Expected a failure")
        } catch {
            #expect(error == .rejected(code: "not_found"))
        }
        #expect(backend.requestCount == before + 1)
        #expect(recorder.waits.isEmpty)
        backend.setMode(.forbidden)
        #expect(await me(client) == .forbidden)
        #expect(backend.requestCount == before + 2)
    }

    // MARK: 429 and Retry-After

    @Test func aShortRetryAfterIsWaitedOutExactlyAndNotSooner() async throws {
        let client = client()
        try await signedIn(client)
        backend.setMode(.rateLimited(retryAfterSeconds: 2), times: 1)
        #expect(await me(client) == nil)
        #expect(recorder.waits == [.seconds(2)])
    }

    @Test func aRateLimitThatKeepsAnsweringIsGivenUpOnAfterTheBoundedTries() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.rateLimited(retryAfterSeconds: 1))
        #expect(await me(client) == .rateLimited(retryAfterSeconds: 1))
        #expect(backend.requestCount == before + 3)
        #expect(recorder.waits == [.seconds(1), .seconds(1)])
    }

    @Test func aLongRetryAfterIsHandedToTheScreenWithoutWaiting() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.rateLimited(retryAfterSeconds: 45))
        #expect(await me(client) == .rateLimited(retryAfterSeconds: 45))
        #expect(backend.requestCount == before + 1)
        #expect(recorder.waits.isEmpty)
    }

    @Test func retryAfterIsReadAsSecondsOrAsADate() throws {
        func response(_ value: String?) throws -> HTTPURLResponse {
            let url = try #require(URL(string: "https://example.invalid/"))
            let fields = value.map { ["Retry-After": $0] }
            return try #require(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: fields))
        }
        let now = Date(timeIntervalSince1970: 1_792_567_200)  // Wed, 21 Oct 2026 07:20:00 GMT
        #expect(APIClient.retryAfter(try response("30"), nil, now: now) == 30)
        #expect(APIClient.retryAfter(try response(" 7 "), nil, now: now) == 7)
        #expect(APIClient.retryAfter(try response("Wed, 21 Oct 2026 07:28:00 GMT"), nil, now: now) == 480)
        // A date already past means now, not a negative wait.
        #expect(APIClient.retryAfter(try response("Wed, 21 Oct 2026 07:00:00 GMT"), nil, now: now) == 0)
        // Nonsense and negatives are ignored, and the envelope's own number is used if it has one.
        #expect(APIClient.retryAfter(try response("soon"), nil, now: now) == nil)
        #expect(APIClient.retryAfter(try response("-5"), nil, now: now) == nil)
        #expect(APIClient.retryAfter(try response(nil), nil, now: now) == nil)
    }

    // MARK: 500 and 503

    @Test func serverErrorsAreRetriedWithBackoffThenGivenUpOn() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.serverError)
        #expect(await me(client) == .serverError)
        #expect(backend.requestCount == before + 3)
        // 0.4 s then 0.8 s, each with up to a quarter more at random.
        #expect(recorder.waits.count == 2)
        #expect(recorder.waits[0] >= .milliseconds(400) && recorder.waits[0] <= .milliseconds(500))
        #expect(recorder.waits[1] >= .milliseconds(800) && recorder.waits[1] <= .milliseconds(1000))
    }

    @Test func unavailableWithoutAnyHintIsRetriedWithBackoffThenGivenUpOn() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.unavailable(retryAfterSeconds: nil))
        #expect(await me(client) == .unavailable(retryAfterSeconds: nil))
        #expect(backend.requestCount == before + 3)
        #expect(recorder.waits.count == 2)
    }

    @Test func unavailableWithAShortRetryAfterIsWaitedOutThenGivenUpOn() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.unavailable(retryAfterSeconds: 1))
        #expect(await me(client) == .unavailable(retryAfterSeconds: 1))
        #expect(backend.requestCount == before + 3)
        #expect(recorder.waits == [.seconds(1), .seconds(1)])
    }

    @Test func unavailableWithALongRetryAfterIsHandedToTheScreen() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.unavailable(retryAfterSeconds: 120))
        #expect(await me(client) == .unavailable(retryAfterSeconds: 120))
        #expect(backend.requestCount == before + 1)
    }

    @Test func aRequestThatIsNotSafeToRepeatIsNotRetriedAfterAServerError() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.serverError)
        do {
            _ = try await client.send(
                APIV1.attestChallenge, body: Optional<APIV1.SessionRequest>.none, as: APIV1.AttestChallenge.self)
            Issue.record("Expected a failure")
        } catch {
            #expect(error == .serverError)
        }
        #expect(backend.requestCount == before + 1)
    }

    // MARK: Malformed answers

    @Test func malformedJSONIsReportedAndNotRetried() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.malformedJSON)
        #expect(await me(client) == .invalidResponse)
        #expect(backend.requestCount == before + 1)
        #expect(recorder.waits.isEmpty)
    }

    // MARK: Still running

    @Test(.timeLimit(.minutes(1)))
    func anActionThatIsStillRunningIsAskedAboutAgainWithTheSameKey() async throws {
        let client = client(RetryPolicy(requestTimeout: .seconds(5), timingOverrides: [:]))
        try await signedIn(client)
        let service = try await paid(client)
        _ = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        // Three answers of "still running", more than `maxAttempts` (3): asking again isn't a
        // failed try, so it doesn't use the tries up.
        backend.setMode(.actionInProgress(retryAfterSeconds: 1), times: 3)
        let receipt = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        #expect(recorder.waits == [.seconds(1), .seconds(1), .seconds(1)])
        #expect(receipt.usage.usedToday == 2)
        #expect(backend.paidJobsRun == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func anActionThatNeverFinishesIsHandedBackAsBusyAtTheDeadline() async throws {
        let policy = RetryPolicy(
            requestTimeout: .seconds(5), overallDeadline: .milliseconds(1500), timingOverrides: [:])
        let client = client(policy, realSleep: true)
        try await signedIn(client)
        let service = try await paid(client)
        _ = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        backend.setMode(.actionInProgress(retryAfterSeconds: 1))
        let started = ContinuousClock.now
        do {
            _ = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
            Issue.record("Expected a failure")
        } catch {
            #expect(error == .busy(retryAfterSeconds: 1))
        }
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    // MARK: Cancellation

    @Test(.timeLimit(.minutes(1)))
    func leavingAScreenDuringABackoffWaitStopsTheCallAndSendsNothingMore() async throws {
        let client = client(realSleep: true)
        try await signedIn(client)
        backend.setMode(.serverError)
        let before = backend.requestCount
        let call = Task { await me(client) }
        // The first try fails at once, and the 0.4 s wait begins.
        try await Task.sleep(for: .milliseconds(200))
        call.cancel()
        #expect(await call.value == .cancelled)
        try await Task.sleep(for: .milliseconds(600))
        #expect(backend.requestCount == before + 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingARequestInFlightEndsItAtOnce() async throws {
        let client = client()
        try await signedIn(client)
        backend.setMode(.slow(seconds: 30))
        let started = ContinuousClock.now
        let call = Task { await me(client) }
        try await Task.sleep(for: .milliseconds(200))
        call.cancel()
        #expect(await call.value == .cancelled)
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test(.timeLimit(.minutes(1)))
    func aCancelledPaidRequestIsNotChargedTwiceWhenAskedAgainWithItsKey() async throws {
        let client = client()
        try await signedIn(client)
        let service = try await paid(client)
        _ = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        let attempt = PaidActionAttempt(Self.swap)
        // The request reaches the server, which does the work; the answer is slow, and she leaves.
        backend.setMode(.slow(seconds: 30), times: 1)
        let call = Task { () async -> CloudLimitProblem? in
            do throws(CloudLimitProblem) {
                _ = try await attempt.run(using: service)
                return nil
            } catch {
                return error
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        call.cancel()
        #expect(await call.value == .account(.cancelled))
        #expect(backend.paidJobsRun == 2)
        // She comes back and asks again. The same attempt has the same key, so the server
        // answers from its record: nothing runs, and nothing more is counted.
        let again = try await attempt.run(using: service)
        #expect(again.replayed)
        #expect(again.usage.usedToday == 2)
        #expect(backend.paidJobsRun == 2)
    }

    @Test func anAttemptSendsOneKeyForEveryRetryAndANewActionGetsANewOne() async throws {
        let first = PaidActionAttempt(Self.swap)
        let second = PaidActionAttempt(Self.swap)
        #expect(first.idempotencyKey == first.idempotencyKey)
        #expect(first.idempotencyKey != second.idempotencyKey)
        #expect(first.idempotencyKey.hasPrefix("idem_"))
    }

    // MARK: Offline state

    @Test func thePathMonitorsAnswersMapToOnlineAndOffline() {
        #expect(PathConnectivitySource.state(for: .satisfied) == .online)
        #expect(PathConnectivitySource.state(for: .unsatisfied) == .offline)
        // A connection that starts on demand is not called offline: the request itself starts it.
        #expect(PathConnectivitySource.state(for: .requiresConnection) == .unknown)
    }

    @Test(.timeLimit(.minutes(1)))
    func theRealPathMonitorReportsAStateAndStopsWhenNobodyListens() async {
        var iterator = PathConnectivitySource().states().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first != nil)
    }
}
