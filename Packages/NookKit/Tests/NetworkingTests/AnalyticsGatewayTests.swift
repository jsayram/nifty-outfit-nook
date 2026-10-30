import Foundation
import Models
import Synchronization
import Testing

@testable import Networking

/// F1c (D24): "Help improve the app" on the gateway. The queue goes as {"events": [...]} with
/// ISO 8601 hours to POST /v1/analytics/events with no account token, App Attest key or
/// Idempotency-Key, only once each event's hour is over; Delete my analytics data asks
/// POST /v1/analytics/deletion with the analytics ID.
@Suite("Analytics gateway")
struct AnalyticsGatewayTests {
    let backend: FakeBackend
    let clock: Clock

    final class Clock: Sendable {
        let time = Mutex(Date(timeIntervalSince1970: 1_800_000_000 + 1_234))
        func advance(_ seconds: TimeInterval) { time.withLock { $0 += seconds } }
        var now: Date { time.withLock { $0 } }
    }

    init() {
        let clock = Clock()
        self.clock = clock
        backend = FakeBackend(now: { clock.now })
    }

    /// The client signs in with a token for everything else; analytics must never use it.
    func endpoint() async throws -> GatewayAnalyticsEndpoint {
        let auth = FakeAuthProvider(subject: "lily")
        try await auth.signInWithApple()
        let client = APIClient(
            baseURL: backend.baseURL,
            session: APIClient.makeSession(protocolClasses: [FakeBackendURLProtocol.self]), auth: auth)
        return GatewayAnalyticsEndpoint(client: client)
    }

    func analytics(_ endpoint: any AnalyticsEndpoint) -> OptInAnalytics {
        let clock = clock
        return OptInAnalytics(
            settings: InMemoryAnalyticsSettingsStore(), endpoint: endpoint,
            context: AnalyticsContext(appVersion: "1.0", systemVersion: "27.0", deviceClass: .iPhone),
            now: { clock.now })
    }

    @Test func eventsGoOnceTheirHourIsOverWithNoTokenOrKey() async throws {
        let analytics = try await analytics(endpoint())
        analytics.setOn(true)
        analytics.record(.styleFinished, .succeeded)
        analytics.record(.tryOnFinished, .failed)
        // Right after the events nothing goes, even when asked.
        await analytics.flush()
        #expect(backend.analyticsEvents.isEmpty && analytics.queued.count == 2)

        clock.advance(3_600)
        await analytics.flush()
        let kept = backend.analyticsEvents
        #expect(kept.count == 2 && analytics.queued.isEmpty)
        // The fake refuses any request carrying Authorization, an App Attest key or an
        // Idempotency-Key, so these arrived without them. The hour is a whole ISO 8601 hour.
        let id = try #require(kept.first?.record.analyticsID)
        #expect(kept.allSatisfy { $0.record.analyticsID == id })
        #expect(kept.map(\.record.hour) == ["2027-01-15T08:00:00Z", "2027-01-15T08:00:00Z"])
        #expect(backend.accountCount == 0)
    }

    @Test func theBodyIsTheContractsBatch() throws {
        let record = AnalyticsRecord(
            event: .askFinished, outcome: .cancelled, hour: Date(timeIntervalSince1970: 1_800_000_000 - 3_600),
            appVersion: "1.0", systemVersion: "27.0.1", deviceClass: .iPad, consentVersion: "analytics-1",
            analyticsID: "3f2a8c1e-7b4d-4e9a-9c0f-5d6e7a8b9c0d")
        let data = try APIV1.encoder().encode(APIV1.AnalyticsBatch([record]))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["events"])
        let event = try #require((object["events"] as? [[String: Any]])?.first)
        #expect(event["hour"] as? String == "2027-01-15T07:00:00Z")
        #expect(event["deviceClass"] as? String == "iPad" && event["event"] as? String == "askFinished")
    }

    @Test func aFullQueueFitsInOneBatch() throws {
        // 100 events, the queue's most, with the longest versions the contract allows.
        let record = AnalyticsRecord(
            event: .tryOnFinished, outcome: .succeeded, hour: Date(timeIntervalSince1970: 1_800_000_000),
            appVersion: "9999.9999.9999.9999", systemVersion: "9999.9999.9999.9999", deviceClass: .iPhone,
            consentVersion: "analytics-1", analyticsID: "3f2a8c1e-7b4d-4e9a-9c0f-5d6e7a8b9c0d")
        let records = Array(repeating: record, count: OptInAnalytics.maximumEvents)
        let data = try APIV1.encoder().encode(APIV1.AnalyticsBatch(records))
        #expect(data.count <= APIV1.sendAnalytics.maxBodyBytes)
    }

    @Test func deleteMyAnalyticsDataSendsTheIDAndTheServerForgetsIt() async throws {
        let analytics = try await analytics(endpoint())
        analytics.setOn(true)
        analytics.record(.styleFinished, .succeeded)
        let id = try #require(analytics.queued.first?.analyticsID)
        clock.advance(3_600)
        await analytics.flush()
        #expect(backend.analyticsEvents.count == 1)

        #expect(await analytics.deleteMyData())
        #expect(backend.deletedAnalyticsIDs == [id])
        #expect(backend.analyticsEvents.isEmpty)
    }

    @Test func aBatchTheServerWontEverTakeIsDropped() async throws {
        let clock = clock
        let analytics = OptInAnalytics(
            settings: InMemoryAnalyticsSettingsStore(), endpoint: try await endpoint(),
            context: AnalyticsContext(appVersion: "1.0 beta", systemVersion: "27.0", deviceClass: .iPhone),
            now: { clock.now })
        analytics.setOn(true)
        analytics.record(.styleFinished, .succeeded)
        clock.advance(3_600)
        await analytics.flush()
        #expect(backend.analyticsEvents.isEmpty && analytics.queued.isEmpty)
    }

    @Test func aBatchThatCouldntGoIsKept() async throws {
        let analytics = try await analytics(endpoint())
        analytics.setOn(true)
        analytics.record(.styleFinished, .succeeded)
        clock.advance(3_600)
        backend.setMode(.unavailable(retryAfterSeconds: 60), times: 1)
        await analytics.flush()
        #expect(analytics.queued.count == 1)
        await analytics.flush()
        #expect(analytics.queued.isEmpty && backend.analyticsEvents.count == 1)
    }

    @Test func refusalsMapToDropOrKeep() {
        #expect(GatewayAnalyticsEndpoint.error(for: .rejected(code: "invalid_request")) is AnalyticsBatchRefused)
        #expect(GatewayAnalyticsEndpoint.error(for: .consentRequired) is AnalyticsBatchRefused)
        #expect(!(GatewayAnalyticsEndpoint.error(for: .offline) is AnalyticsBatchRefused))
        #expect(!(GatewayAnalyticsEndpoint.error(for: .rateLimited(retryAfterSeconds: 60)) is AnalyticsBatchRefused))
        #expect(!(GatewayAnalyticsEndpoint.error(for: .unavailable(retryAfterSeconds: nil)) is AnalyticsBatchRefused))
    }

    // MARK: The fake backend checks what the real one checks

    func post(_ path: String, body: Data, headers: [String: String] = [:]) async throws -> (Int, String?) {
        var request = URLRequest(url: backend.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = body
        let session = APIClient.makeSession(protocolClasses: [FakeBackendURLProtocol.self])
        let (data, response) = try await session.data(for: request)
        let status = try #require(response as? HTTPURLResponse).statusCode
        return (status, try? JSONDecoder().decode(APIV1.ErrorEnvelope.self, from: data).error.code)
    }

    /// A golden batch with its hour moved to the fake's own clock, so it isn't too old to keep.
    func goldenBatch() throws -> Data {
        let text = try String(decoding: ContractTests.data("v1/examples/analytics-events.request.json"), as: UTF8.self)
        return Data(text.replacing("2026-10-29T14:00:00Z", with: "2027-01-15T08:00:00Z").utf8)
    }

    @Test(arguments: ["Authorization", "X-Nook-Attest-Key", "X-Nook-Assertion", "Idempotency-Key"])
    func aRequestCarryingAnAccountOrDeviceKeyIsRefused(header: String) async throws {
        let (status, code) = try await post("/v1/analytics/events", body: goldenBatch(), headers: [header: "x"])
        #expect(status == 400 && code == "invalid_request")
        #expect(backend.analyticsEvents.isEmpty)
    }

    @Test func theGoldenBatchIsAccepted() async throws {
        let (status, _) = try await post("/v1/analytics/events", body: goldenBatch())
        #expect(status == 202)
        #expect(backend.analyticsEvents.count == 2)
    }

    @Test(arguments: [
        ("analytics-events.request.bad_id.json", "/v1/analytics/events"),
        ("analytics-events.request.device_model.json", "/v1/analytics/events"),
        ("analytics-events.request.free_text.json", "/v1/analytics/events"),
        ("analytics-events.request.too_many.json", "/v1/analytics/events"),
        ("analytics-events.request.user_id.json", "/v1/analytics/events"),
        ("analytics-deletion.request.account.json", "/v1/analytics/deletion"),
        ("analytics-deletion.request.no_id.json", "/v1/analytics/deletion"),
    ])
    func rejectsTheContractsInvalidAnalyticsExamples(file: String, path: String) async throws {
        let (status, code) = try await post(path, body: ContractTests.data("v1/examples/invalid/\(file)"))
        #expect(status == 400 && code == "invalid_request", "\(file)")
        #expect(backend.analyticsEvents.isEmpty && backend.deletedAnalyticsIDs.isEmpty)
    }

    @Test func anHourThatIsntTheStartOfOneIsRefused() async throws {
        let text = try String(decoding: goldenBatch(), as: UTF8.self)
        let body = Data(text.replacing("08:00:00Z", with: "08:17:00Z").utf8)
        let (status, code) = try await post("/v1/analytics/events", body: body)
        #expect(status == 400 && code == "invalid_request")
    }
}
