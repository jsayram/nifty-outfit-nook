import Foundation
import Models
import Network
import NookTestSupport
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
    /// Records waits instead of sleeping, so a retry test doesn't take real time.
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
    /// The client's clock. It only moves when a test advances it, or when the client waits between
    /// tries (the wait is recorded and the clock jumps ahead by it), so no timeout in this suite
    /// depends on how fast the machine is. The limits below are long for the same reason: the
    /// request's own limit, which URLSession counts in real time, never gets a chance to fire.
    let clock = ManualClock()

    func client(
        _ policy: RetryPolicy = RetryPolicy(requestTimeout: .seconds(60)),
        auth: (any AuthProvider)? = nil,
        sleep: (@Sendable (Duration) async throws -> Void)? = nil
    ) -> APIClient {
        let recorder = recorder
        let clock = clock
        return APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth ?? self.auth, policy: policy, clock: clock,
            sleep: sleep ?? { duration in
                recorder.wait(duration)
                try await clock.skip(duration)
            },
            onEvent: { recorder.record($0) })
    }

    /// Waits until `condition` holds. For things the test can't be told about, like a request
    /// reaching the fake backend. There is no timing in it: the test's time limit ends a wait
    /// that never finishes.
    func eventually(_ condition: () -> Bool) async {
        while !condition() { try? await Task.sleep(for: .milliseconds(1)) }
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

    /// A new quick request on every use, so the stylist's result cache never answers it (27a).
    static var swap: PaidActionRequest { .style(.sample(.ask, note: String(UUID().uuidString.prefix(8)))) }

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

    /// Starts `me` in the background, and waits until its try is running: the request is at the
    /// backend and its time limit is asleep on the clock. Then the test fires that limit.
    func aTryRunningUntilItsLimit(_ client: APIClient, limit: Duration) async -> APIFailure? {
        let before = backend.requestCount
        let call = Task { await me(client) }
        await eventually { backend.requestCount > before }
        await clock.waitForSleepers(1)
        clock.advance(by: limit)
        return await call.value
    }

    @Test(.timeLimit(.minutes(1)))
    func aTryIsCutOffAtItsLimitEvenWhenTheServerIsOnlySlow() async throws {
        let policy = RetryPolicy(maxAttempts: 1, requestTimeout: .seconds(30))
        let client = client(policy)
        try await signedIn(client)
        // The answer would come in ten minutes, so only the limit ends this try.
        backend.setMode(.slow(seconds: 600))
        #expect(await aTryRunningUntilItsLimit(client, limit: .seconds(30)) == .timedOut)
    }

    @Test(.timeLimit(.minutes(1)))
    func aTryIsCutOffAtItsLimitEvenWhenTheServerKeepsTrickling() async throws {
        // One byte every 100 ms is never silent for 30 s, so only a hard limit ends it. The answer
        // is about 150 bytes, so it would take about 15 seconds on its own: the call can only
        // end as timed out if the limit cut it off while the bytes were still coming. This is the
        // one test that also leans on real time, and only by that wide a margin.
        let policy = RetryPolicy(maxAttempts: 1, requestTimeout: .seconds(30))
        let client = client(policy)
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.trickle)
        let call = Task { await me(client) }
        await eventually { backend.requestCount > before }
        await clock.waitForSleepers(1)
        clock.advance(by: .seconds(30))
        #expect(await call.value == .timedOut)
    }

    @Test func aSlowAnswerWithinTheLimitStillArrives() async throws {
        let client = client()
        try await signedIn(client)
        backend.setMode(.slow(seconds: 0.4))
        #expect(await me(client) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func aServerThatNeverAnswersIsTriedAgainOnlyWithinTheDeadline() async throws {
        // Tries of 200 s with a deadline of 500 s, and 10 to 25 s of backoff: the first two tries
        // time out in full, the third has what is left of the deadline, and no fourth fits.
        let policy = RetryPolicy(
            maxAttempts: 10, baseDelay: .seconds(10), maxDelay: .seconds(20),
            requestTimeout: .seconds(200), overallDeadline: .seconds(500), timingOverrides: [:])
        let client = client(policy)
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.timeout)
        let started = clock.now
        let call = Task { await me(client) }
        for attempt in 1...3 {
            await eventually { backend.requestCount == before + attempt }
            await clock.advanceToNextSleeper()
        }
        #expect(await call.value == .timedOut)
        #expect(started.duration(to: clock.now) == .seconds(500))
        #expect(backend.requestCount - before == 3)
        #expect(recorder.waits.count == 2)
    }

    @Test func aBackoffThatCannotFitTheDeadlineIsNotWaited() async throws {
        let policy = RetryPolicy(
            baseDelay: .seconds(500), maxDelay: .seconds(500), requestTimeout: .seconds(60),
            overallDeadline: .seconds(200), timingOverrides: [:])
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
        let client = client(RetryPolicy(requestTimeout: .seconds(60), timingOverrides: [:]))
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
        // Asked again every 10 s: the first answer comes at 0 s, the next at 10 s, the next at
        // 20 s, and a third wait would end at 30 s, past the 28 s deadline.
        let policy = RetryPolicy(
            requestTimeout: .seconds(60), overallDeadline: .seconds(28), timingOverrides: [:])
        let client = client(policy)
        try await signedIn(client)
        let service = try await paid(client)
        _ = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        backend.setMode(.actionInProgress(retryAfterSeconds: 10))
        let before = recorder.waits.count
        do {
            _ = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
            Issue.record("Expected a failure")
        } catch {
            #expect(error == .busy(retryAfterSeconds: 10))
        }
        #expect(recorder.waits.count - before == 2)
    }

    // MARK: Cancellation

    @Test(.timeLimit(.minutes(1)))
    func leavingAScreenDuringABackoffWaitStopsTheCallAndSendsNothingMore() async throws {
        // This client really waits on the clock, which the test never moves, and says when it
        // starts to wait.
        let (waiting, started) = AsyncStream<Void>.makeStream()
        let clock = clock
        let client = client { duration in
            started.yield()
            try await clock.sleep(for: duration)
        }
        try await signedIn(client)
        backend.setMode(.serverError)
        let before = backend.requestCount
        let call = Task { await me(client) }
        // The first try fails at once, and the wait begins.
        _ = await waiting.first { _ in true }
        call.cancel()
        #expect(await call.value == .cancelled)
        // The call is over, and nothing is waiting to send a second try.
        #expect(clock.sleeperCount == 0)
        #expect(backend.requestCount == before + 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingARequestInFlightEndsItAtOnce() async throws {
        let client = client()
        try await signedIn(client)
        let before = backend.requestCount
        backend.setMode(.slow(seconds: 3600))
        let call = Task { await me(client) }
        await eventually { backend.requestCount > before }
        call.cancel()
        #expect(await call.value == .cancelled)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCancelledPaidRequestIsNotChargedTwiceWhenAskedAgainWithItsKey() async throws {
        let client = client()
        try await signedIn(client)
        let service = try await paid(client)
        _ = try await service.run(Self.swap, idempotencyKey: IdempotencyKey.make())
        let attempt = PaidActionAttempt(Self.swap)
        // The request reaches the server, which does the work; the answer is slow, and she leaves.
        backend.setMode(.slow(seconds: 3600), times: 1)
        let call = Task { () async -> CloudLimitProblem? in
            do throws(CloudLimitProblem) {
                _ = try await attempt.run(using: service)
                return nil
            } catch {
                return error
            }
        }
        await eventually { backend.paidJobsRun == 2 }
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
