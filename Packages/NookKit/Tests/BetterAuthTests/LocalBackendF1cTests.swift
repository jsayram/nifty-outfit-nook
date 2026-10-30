import Foundation
import Models
import Testing

@testable import BetterAuth
@testable import Networking

/// F1c's checkpoint against a real local Convex backend from the private backend repo (branch
/// `feature/f1b-follow-ups`), run the same way as `LocalBackendTests`: the backend's App Attest
/// in mock mode (the app's fake attester) and its stand-in stylist (no provider key, no AI call).
///
///     TEST_RUNNER_NOOK_LOCAL_SITE_URL=http://127.0.0.1:<site port> \
///     TEST_RUNNER_NOOK_FAKE_APPLE_URL=http://127.0.0.1:<port> \
///     scripts/test.sh -only-testing:BetterAuthTests/LocalBackendF1cTests
@Suite("F1c on a local backend", .enabled(if: LocalBackend.addresses != nil))
struct LocalBackendF1cTests {
    static let now = Date()

    struct Signed {
        let client: APIClient
        let paid: GatewayPaidActionService
        let attestation: AttestationSession
        let account: GatewayAccountService
    }

    /// Signed in through Better Auth, with an account and the mock App Attest key. A fixed Apple
    /// subject per test, so the local account can be given styling access once with
    /// `npx convex run admin:setPlanOverride` (styling needs it, 30c).
    @MainActor
    func signedIn(_ subject: String) async throws -> Signed {
        let (site, issuer) = try #require(LocalBackend.addresses)
        let apple = try #require(LocalFakeAppleIssuer(issuer: issuer, subject: "000123.\(subject).0042"))
        let session = APIClient.makeSession()
        let auth = BetterAuthProvider(baseURL: site, session: session, store: MemorySessionStore(), apple: apple)
        let client = APIClient(baseURL: site, session: session, auth: auth)
        let attestation = AttestationSession(
            attester: FakeDeviceAttester(), store: MemoryAttestKeyStore(), client: client)
        let account = GatewayAccountService(auth: auth, client: client, appVersion: "0.1.0", attestation: attestation)
        _ = try await account.signIn()
        return Signed(
            client: client, paid: GatewayPaidActionService(client: client, attestation: attestation),
            attestation: attestation, account: account)
    }

    static func context(_ measurements: StyleCall.Measurements?) -> StylingContext {
        let pieces = [
            Garment(id: .init("g-blouse"), name: "Cream blouse", category: .top, colors: [.cream], addedAt: now),
            Garment(id: .init("g-trousers"), name: "Olive trousers", category: .bottom, colors: [.olive], addedAt: now),
            Garment(id: .init("g-loafers"), name: "Brown loafers", category: .shoes, colors: [.brown], addedAt: now),
        ]
        return StylingContext(
            request: StyleRequest(id: .random(), occasion: .office, weatherChoice: .indoors, createdAt: now),
            eligibleGarments: pieces, now: now, calendar: Calendar(identifier: .gregorian), measurements: measurements)
    }

    static let measurements = StyleCall.Measurements(heightCm: 160, waistCm: 71, hipsCm: 97, inseamCm: 74, weightKg: 58)

    @Test @MainActor func underStylist2TheStyleRequestWithMeasurementsIsAccepted() async throws {
        let signed = try await signedIn("f1cstylisttwo")
        let consent = InMemoryStylistConsentStore(StylistConsent(agreedAt: Self.now))
        let stylist = CloudStylist(paid: signed.paid, consent: consent)
        let outcome = try await stylist.style(Self.context(Self.measurements))
        #expect(outcome.result != nil)
        await signed.account.signOut()
    }

    /// The backend refuses measurements under stylist-1 with consent_required, and takes stylist-1
    /// without them. The app can't build that body (`StyleCall` drops them), so it's built here.
    @Test @MainActor func underStylist1TheBackendRefusesMeasurements() async throws {
        let signed = try await signedIn("f1cstylistone")
        var body = APIV1.StyleRequest(StyleCall.outfit(from: Self.context(nil), consentVersion: "stylist-1"))
        #expect(body.measurements == nil)
        body.measurements = APIV1.StylistMeasurements(Self.measurements)
        await #expect(throws: APIFailure.consentRequired) {
            try await signed.client.send(
                APIV1.style, body: body, idempotencyKey: IdempotencyKey.make(), signer: signed.attestation,
                as: APIV1.StyleResponse.self)
        }
        body.measurements = nil
        let answer = try await signed.client.send(
            APIV1.style, body: body, idempotencyKey: IdempotencyKey.make(), signer: signed.attestation,
            as: APIV1.StyleResponse.self)
        #expect(answer.result.styleAnswer != nil)
        await signed.account.signOut()
    }

    /// Analytics go through the same signed-in client and still carry no token: the backend refuses
    /// any analytics request with Authorization, an App Attest key or an Idempotency-Key.
    @Test @MainActor func analyticsAreAcceptedWithoutATokenThenDeleted() async throws {
        let signed = try await signedIn("f1canalytics")
        let endpoint = GatewayAnalyticsEndpoint(client: signed.client)
        let thisHour = (Date().timeIntervalSince1970 / 3_600).rounded(.down) * 3_600
        let lastHour = Date(timeIntervalSince1970: thisHour - 3_600)
        let id = UUID().uuidString.lowercased()
        let records = [AnalyticsEvent.styleFinished, .askFinished].map {
            AnalyticsRecord(
                event: $0, outcome: .succeeded, hour: lastHour, appVersion: "1.0", systemVersion: "27.0",
                deviceClass: .iPhone, consentVersion: AnalyticsSettings.currentVersion, analyticsID: id)
        }
        let receipt = try await signed.client.send(
            APIV1.sendAnalytics, body: APIV1.AnalyticsBatch(records), as: APIV1.AnalyticsReceipt.self)
        #expect(receipt.accepted == 2)
        try await endpoint.send(records)
        try await endpoint.deleteEvents(analyticsID: id)
        // An old consent version is refused for good, so the app drops the batch.
        var old = records
        old[0].consentVersion = "analytics-0"
        old[1].consentVersion = "analytics-0"
        await #expect(throws: AnalyticsBatchRefused.self) { try await endpoint.send(old) }
        await signed.account.signOut()
    }
}
