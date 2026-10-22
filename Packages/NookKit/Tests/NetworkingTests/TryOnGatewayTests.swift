import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

@testable import Networking

/// 33a: POST /v1/try-on through the real client, App Attest stand-in and fake backend: only the
/// faceless photo and garment photos go, the first answer is "still running", the same key and
/// body are sent until the picture comes back, and it runs and counts once.
@Suite("Try-on gateway")
struct TryOnGatewayTests {
    /// The backend's clock, moved by the client's waits so "ready in 3 seconds" takes no time.
    let date = DateCell()
    let backend: FakeBackend
    let auth = FakeAuthProvider(subject: "lily")
    let policy = RetryPolicy(requestTimeout: .seconds(60))
    let clock = ManualClock()

    init() {
        let date = date
        backend = FakeBackend(now: { date.value.withLock { $0 } })
    }

    func service() async throws -> GatewayPaidActionService {
        let clock = clock
        let date = date
        let client = APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(policy: policy, protocolClasses: [FakeBackendURLProtocol.self]),
            auth: auth, policy: policy, clock: clock,
            sleep: { duration in
                date.value.withLock { $0 = $0.addingTimeInterval(Double(duration.components.seconds)) }
                try await clock.skip(duration)
            })
        try await auth.signInWithApple()
        _ = try await GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0").whoAmI()
        let session = AttestationSession(attester: FakeDeviceAttester(), store: MemoryAttestKeyStore(), client: client)
        return GatewayPaidActionService(client: client, attestation: session, entitlementHint: EntitlementHintSource())
    }

    @Test func thePictureComesBackAfterStillRunningAndIsCountedOnce() async throws {
        backend.setTryOn(.normal)
        let paid = try await service()
        let call = TryOnCall.sample(note: "wait")
        let key = IdempotencyKey.make()
        let receipt = try await paid.run(.tryOn(call), idempotencyKey: key)
        let image = try #require(receipt.tryOnImage)
        #expect(image.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(!receipt.replayed && receipt.usage.usedToday == 1)
        #expect(backend.paidJobsRun == 1)
        // What left the phone: the faceless photo and the garment photos with ID, category and
        // kind, and nothing else.
        let sent = try #require(backend.tryOnRequests.first)
        #expect(sent == APIV1.TryOnRequest(call))
        #expect(sent.person.data == call.person.base64EncodedString())
        #expect(sent.garments.map(\.kind) == ["blouse"])
        // Asking again with the same key gets the same picture, not counted again.
        let again = try await paid.run(.tryOn(call), idempotencyKey: key)
        #expect(again.replayed && again.tryOnImage == image && again.usage.usedToday == 1)
        #expect(backend.paidJobsRun == 1)
    }

    @Test func theBodyOnTheWireHasOnlyTheContractsFields() throws {
        let body = try APIV1.encoder().encode(APIV1.TryOnRequest(.sample()))
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(object.keys) == ["contextRevision", "consentVersion", "person", "garments"])
        let garment = try #require((object["garments"] as? [[String: Any]])?.first)
        #expect(Set(garment.keys) == ["id", "category", "kind", "image"])
    }

    @Test func aFailedPictureIsNotCounted() async throws {
        backend.setTryOn(.fails)
        let paid = try await service()
        do {
            _ = try await paid.run(.tryOn(.sample(note: "fails")), idempotencyKey: IdempotencyKey.make())
            Issue.record("expected a failure")
        } catch {
            guard case .didNotFinish = error else {
                Issue.record("got \(error)")
                return
            }
        }
        #expect(try await paid.usage().allowance(.tryOn)?.usedToday == 0)
    }

    @Test func consentToAnotherTextIsRefusedBeforeAnythingRuns() async throws {
        let paid = try await service()
        var call = TryOnCall.sample(note: "consent")
        call.consentVersion = "tryon-0"
        do {
            _ = try await paid.run(.tryOn(call), idempotencyKey: IdempotencyKey.make())
            Issue.record("expected consent_required")
        } catch {
            #expect(error == .needsConsent)
        }
        #expect(backend.paidJobsRun == 0)
    }
}

/// The fake backend's date, shared with the client's waits.
final class DateCell: Sendable {
    let value = Mutex(TestTime.now)
}
