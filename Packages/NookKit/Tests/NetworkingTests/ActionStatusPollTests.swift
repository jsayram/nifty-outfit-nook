import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Networking

/// Phase 35: a try-on is polled by its action ID, not by sending the photos again. Through the
/// real client, the App Attest stand-in and the fake backend, with time moved only by the client's
/// own waits (a `ManualClock`): the photos go up once, a poll carries only the ID, a relaunch or a
/// late answer carries on with the stored ID, and the ways it can end (failed, expired, no such
/// action, the status call's own limit) each say what they should.
@Suite("Action status polling")
struct ActionStatusPollTests {
    /// The backend's clock, moved by the client's waits so "ready in 15 seconds" takes no time.
    let date = DateCell()
    let backend: FakeBackend
    let auth = FakeAuthProvider(subject: "lily")
    let clock = ManualClock()
    let events = EventLog()

    init() {
        let date = date
        backend = FakeBackend(now: { date.value.withLock { $0 } })
    }

    func service(policy: RetryPolicy = RetryPolicy(requestTimeout: .seconds(60))) async throws
        -> GatewayPaidActionService
    {
        let clock = clock
        let date = date
        let events = events
        let client = APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth, policy: policy, clock: clock,
            sleep: { duration in
                date.value.withLock { $0 = $0.addingTimeInterval(Double(duration.components.seconds)) }
                try await clock.skip(duration)
            },
            onEvent: { event in events.items.withLock { $0.append(event) } })
        try await auth.signInWithApple()
        _ = try await GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0").whoAmI()
        let session = AttestationSession(attester: FakeDeviceAttester(), store: MemoryAttestKeyStore(), client: client)
        return GatewayPaidActionService(client: client, attestation: session, entitlementHint: EntitlementHintSource())
    }

    /// The bytes one try-on body takes on the wire.
    func bodyBytes(_ call: TryOnCall) throws -> Int {
        try APIV1.encoder().encode(APIV1.TryOnRequest(call)).count
    }

    /// How many waits "still running, asking its status" the client made.
    var statusWaits: Int {
        events.items.withLock {
            $0.filter { if case .retrying(_, _, let reason) = $0 { reason.contains("status") } else { false } }.count
        }
    }

    @Test func thePhotosGoUpOnceAndEveryPollCarriesOnlyTheID() async throws {
        backend.setTryOn(.slow)  // ready 15 seconds after the first ask
        let paid = try await service()
        let call = TryOnCall.sample(note: "poll")
        let started = Mutex<[String]>([])
        let receipt = try await paid.run(
            .tryOn(call), idempotencyKey: IdempotencyKey.make(),
            link: ActionLink { id in started.withLock { $0.append(id) } })

        #expect(receipt.tryOnImage?.starts(with: [0xFF, 0xD8, 0xFF]) == true)
        #expect(!receipt.replayed && receipt.usage.usedToday == 1)
        #expect(backend.paidJobsRun == 1)
        // Sent once: one POST, one body's worth of bytes.
        #expect(backend.tryOnPosts == 1)
        #expect(backend.tryOnUploadedBytes == (try bodyBytes(call)))
        // Followed by the ID the server named, which the caller was told about, once.
        let id = started.withLock { $0.first }
        #expect(started.withLock { $0.count } == 1 && id == receipt.id)
        // 15 seconds at the fake's 2 second pace: several asks, and none of them carried more than the ID.
        #expect(backend.statusRequests >= 7)
        #expect(backend.largestStatusBody < 100)
        #expect(statusWaits >= 7)
    }

    @Test func aRelaunchAsksForTheStatusAndNeverUploadsAgain() async throws {
        backend.setTryOn(.slow)
        let call = TryOnCall.sample(note: "relaunch")
        let key = IdempotencyKey.make()

        // The app is killed (here: the connection ends) right after the server names the action.
        let first = try await service()
        let ids = Mutex<[String]>([])
        let backend = backend
        do {
            _ = try await first.run(
                .tryOn(call), idempotencyKey: key,
                link: ActionLink { id in
                    ids.withLock { $0.append(id) }
                    backend.setMode(.offline, times: 1)
                })
            Issue.record("expected the first run to end early")
        } catch {
            #expect(error == .account(.offline))
        }
        let id = ids.withLock { $0.first }
        #expect(id != nil)
        #expect(backend.tryOnPosts == 1)
        let postsBefore = backend.tryOnUploadedBytes

        // The relaunched app has the stored ID and the same key: it asks for the status only.
        let second = try await service()
        let receipt = try await second.run(.tryOn(call), idempotencyKey: key, link: ActionLink(resume: id))
        #expect(receipt.tryOnImage?.starts(with: [0xFF, 0xD8, 0xFF]) == true)
        #expect(receipt.id == id)
        #expect(backend.tryOnPosts == 1)
        #expect(backend.tryOnUploadedBytes == postsBefore)
        #expect(backend.paidJobsRun == 1)
        #expect(try await second.usage().allowance(.tryOn)?.usedToday == 1)
    }

    @Test func anActionTheServerDoesNotKnowIsAskedTheOldWayOnce() async throws {
        let paid = try await service()
        let call = TryOnCall.sample(note: "stale")
        backend.setTryOn(.normal)
        let stale = "act_" + String(repeating: "0", count: 32)
        let receipt = try await paid.run(
            .tryOn(call), idempotencyKey: IdempotencyKey.make(), link: ActionLink(resume: stale))
        #expect(receipt.tryOnImage != nil)
        // One status ask got 404; then the request was sent, once, and followed by its own ID.
        #expect(backend.tryOnPosts == 1)
        #expect(receipt.id != stale)
    }

    @Test func aFailedPictureEndsThePollAndIsNotCounted() async throws {
        backend.setTryOn(.fails)
        let paid = try await service()
        let key = IdempotencyKey.make()
        do {
            _ = try await paid.run(.tryOn(.sample(note: "fails")), idempotencyKey: key)
            Issue.record("expected a failure")
        } catch {
            // Nothing was counted, and trying again is a new tap with a new key.
            #expect(error == .didNotFinish(retryAfterSeconds: 30))
        }
        #expect(backend.tryOnPosts == 1)
        #expect(try await paid.usage().allowance(.tryOn)?.usedToday == 0)
    }

    @Test func aPictureThatIsNoLongerKeptSaysItDidNotFinish() async throws {
        let paid = try await service()
        let call = TryOnCall.sample(note: "expired")
        let ids = Mutex<[String]>([])
        backend.setTryOn(.normal)
        _ = try await paid.run(
            .tryOn(call), idempotencyKey: IdempotencyKey.make(),
            link: ActionLink { id in ids.withLock { $0.append(id) } })
        backend.expireTryOnResults()
        let id = ids.withLock { $0.first }
        #expect(id != nil)
        do {
            _ = try await paid.run(
                .tryOn(call), idempotencyKey: IdempotencyKey.make(), link: ActionLink(resume: id))
            Issue.record("expected it to be gone")
        } catch {
            #expect(error == .didNotFinish(retryAfterSeconds: nil))
        }
    }

    @Test func theStatusCallsOwnLimitIsWaitedOut() async throws {
        backend.setTryOn(.slow)
        let paid = try await service()
        let backend = backend
        let date = date
        let before = date.value.withLock { $0 }
        let receipt = try await paid.run(
            .tryOn(.sample(note: "limit")), idempotencyKey: IdempotencyKey.make(),
            // The first status ask is told to wait 20 seconds (longer than the client waits on the spot).
            link: ActionLink { _ in backend.setMode(.rateLimited(retryAfterSeconds: 20), times: 1) })
        #expect(receipt.tryOnImage != nil)
        // It waited 10 seconds (its own cap) and carried on; it didn't give up or send the photos again.
        #expect(date.value.withLock { $0 }.timeIntervalSince(before) >= 10)
        #expect(backend.tryOnPosts == 1)
    }

    @Test func aPictureTakingLongerThanTheDeadlineIsPickedUpAgainByItsID() async throws {
        backend.setTryOn(.slow)
        // The deadline for following a try-on is 10 seconds here; the picture takes 15.
        let policy = RetryPolicy(
            requestTimeout: .seconds(60),
            timingOverrides: [APIV1.tryOn.id: EndpointTiming(attemptTimeout: .seconds(30), deadline: .seconds(10))])
        let paid = try await service(policy: policy)
        let call = TryOnCall.sample(note: "deadline")
        let key = IdempotencyKey.make()
        let ids = Mutex<[String]>([])
        let link = ActionLink { id in ids.withLock { $0.append(id) } }
        do {
            _ = try await paid.run(.tryOn(call), idempotencyKey: key, link: link)
            Issue.record("expected it to still be running")
        } catch {
            guard case .busy = error else {
                Issue.record("got \(error)")
                return
            }
        }
        // The caller (the job) asks again later, with the ID it kept: status only.
        let id = ids.withLock { $0.first }
        #expect(id != nil)
        let receipt = try await paid.run(.tryOn(call), idempotencyKey: key, link: ActionLink(resume: id))
        #expect(receipt.tryOnImage != nil)
        #expect(backend.tryOnPosts == 1)
        #expect(backend.paidJobsRun == 1)
    }

    @Test func aRequestThatWasAlreadyDoneStillGetsItsPictureFromTheSameKey() async throws {
        let paid = try await service()
        let call = TryOnCall.sample(note: "old way")
        let key = IdempotencyKey.make()
        backend.setTryOn(.normal)
        let first = try await paid.run(.tryOn(call), idempotencyKey: key)
        // No ID kept (an older app, or a lost one): the same key and body still answer from the record.
        let again = try await paid.run(.tryOn(call), idempotencyKey: key)
        #expect(again.replayed && again.tryOnImage == first.tryOnImage)
        #expect(backend.paidJobsRun == 1)
        #expect(backend.tryOnPosts == 2)
    }

    @Test func aFinishedStylistActionsAnswerComesByStatusToo() async throws {
        // The same service follows a stylist action by its ID. The stand-in stylist answers at once,
        // so this checks the finished half: the answer by status is the answer the 200 gave.
        let base = CloudStylistTests()
        let paid = try await base.paid()
        let call = StyleCall.outfit(from: CloudStylistTests.context(), consentVersion: StylistConsent.currentVersion)
        let key = IdempotencyKey.make()
        let sent = try await paid.run(.style(call), idempotencyKey: key)
        let link = ActionLink(resume: sent.id)
        let viaStatus = try await paid.run(.style(call), idempotencyKey: IdempotencyKey.make(), link: link)
        #expect(viaStatus.id == sent.id)
        #expect(viaStatus.style == sent.style)
        #expect(viaStatus.usage == sent.usage)
        #expect(base.backend.statusRequests == 1)
    }
}

/// The client's events, for counting its waits.
final class EventLog: Sendable {
    let items = Mutex<[APIEvent]>([])
}
