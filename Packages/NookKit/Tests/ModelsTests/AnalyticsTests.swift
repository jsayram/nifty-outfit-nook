import Foundation
import Models
import Synchronization
import Testing

/// "Help improve the app" (F1, D24, PRD 23.1): off by default, allowlisted events only, a queue
/// in memory with its limits, a resettable ID, and Delete my analytics data.
struct AnalyticsTests {
    final class Recording: AnalyticsEndpoint {
        let sent = Mutex<[[AnalyticsRecord]]>([])
        let deleted = Mutex<[String]>([])
        let fails: Bool

        init(fails: Bool = false) { self.fails = fails }

        func send(_ records: [AnalyticsRecord]) async throws {
            if fails { throw NoAnalyticsEndpoint.NotAvailable() }
            sent.withLock { $0.append(records) }
        }

        func deleteEvents(analyticsID: String) async throws {
            if fails { throw NoAnalyticsEndpoint.NotAvailable() }
            deleted.withLock { $0.append(analyticsID) }
        }
    }

    final class Clock: Sendable {
        let time = Mutex(Date(timeIntervalSince1970: 1_800_000_000 + 1_234))
        func advance(_ seconds: TimeInterval) { time.withLock { $0 += seconds } }
    }

    static let context = AnalyticsContext(appVersion: "1.0", systemVersion: "27.0", deviceClass: .iPhone)

    func analytics(_ endpoint: Recording = Recording(), clock: Clock = Clock()) -> OptInAnalytics {
        OptInAnalytics(
            settings: InMemoryAnalyticsSettingsStore(), endpoint: endpoint, context: Self.context,
            now: { clock.time.withLock { $0 } })
    }

    @Test func offByDefaultNothingIsQueued() {
        let analytics = analytics()
        #expect(!analytics.isOn)
        analytics.record(.styleFinished, .succeeded)
        #expect(analytics.queued.isEmpty)
    }

    @Test func anEventCarriesOnlyTheAllowedFields() throws {
        let analytics = analytics()
        analytics.setOn(true)
        analytics.record(.tryOnFinished, .failed)
        let record = try #require(analytics.queued.first)
        #expect(record.event == .tryOnFinished && record.outcome == .failed)
        #expect(record.hour.timeIntervalSince1970.truncatingRemainder(dividingBy: 3_600) == 0)
        #expect(record.consentVersion == AnalyticsSettings.currentVersion)
        #expect(record.appVersion == "1.0" && record.deviceClass == .iPhone)
        // The encoded record has exactly these keys: nothing else can ride along.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        let keys = Set((json ?? [:]).keys)
        #expect(
            keys == [
                "event", "outcome", "hour", "appVersion", "systemVersion", "deviceClass", "consentVersion",
                "analyticsID",
            ])
    }

    @Test func theQueueKeepsAtMostItsLimitAndDropsOldEvents() {
        let clock = Clock()
        let analytics = analytics(clock: clock)
        analytics.setOn(true)
        for _ in 0..<150 { analytics.record(.styleFinished, .succeeded) }
        #expect(analytics.queued.count == min(OptInAnalytics.maximumEvents, OptInAnalytics.maximumBytes / 256))
        clock.advance(OptInAnalytics.keptFor + 7_200)
        analytics.record(.askFinished, .succeeded)
        #expect(analytics.queued.map(\.event) == [.askFinished])
    }

    @Test func turningItOffClearsTheQueueAndTurningItOnMakesANewID() throws {
        let analytics = analytics()
        analytics.setOn(true)
        analytics.record(.styleFinished, .succeeded)
        let first = try #require(analytics.queued.first?.analyticsID)
        analytics.setOn(false)
        #expect(analytics.queued.isEmpty && !analytics.isOn)
        analytics.setOn(true)
        analytics.record(.styleFinished, .succeeded)
        #expect(analytics.queued.first?.analyticsID != first)
    }

    @Test func sendingKeepsEventsWhenItCantAndClearsThemWhenItDid() async {
        let failing = Recording(fails: true)
        let analytics = analytics(failing)
        analytics.setOn(true)
        analytics.record(.styleFinished, .succeeded)
        await analytics.flush()
        #expect(analytics.queued.count == 1)

        let working = Recording()
        let other = self.analytics(working)
        other.setOn(true)
        other.record(.styleFinished, .succeeded)
        await other.flush()
        #expect(other.queued.isEmpty && working.sent.withLock { $0.count } == 1)
    }

    @Test func deleteMyAnalyticsDataAsksTheServerThenResetsTheID() async throws {
        let endpoint = Recording()
        let analytics = analytics(endpoint)
        analytics.setOn(true)
        analytics.record(.styleFinished, .succeeded)
        let id = try #require(analytics.queued.first?.analyticsID)
        #expect(await analytics.deleteMyData())
        #expect(endpoint.deleted.withLock { $0 } == [id])
        #expect(analytics.queued.isEmpty && analytics.isOn)
        analytics.record(.styleFinished, .succeeded)
        #expect(analytics.queued.first?.analyticsID != id)

        let unreachable = self.analytics(Recording(fails: true))
        unreachable.setOn(true)
        #expect(await unreachable.deleteMyData() == false)
    }

    @Test func deleteMyDataErasesTheChoice() async throws {
        let analytics = analytics()
        analytics.setOn(true)
        analytics.record(.styleFinished, .succeeded)
        try await analytics.eraseAll()
        #expect(!analytics.isOn && analytics.queued.isEmpty)
    }
}
