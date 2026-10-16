import Fixtures
import Foundation
import Models
import Testing

/// The in-memory tour progress store (Phase 16a).
struct TourStoreTests {
    @Test func everyFixtureSetStartsAsAFreshInstall() async throws {
        for set in FixtureSet.allCases {
            let services = FixtureServices.make(set: set, now: TestTime.now, calendar: TestTime.calendar)
            #expect(try await services.tours.progress() == .fresh, "\(set)")
        }
    }

    @Test func keepsTheLatestRecordAndTheSwitch() async throws {
        let store = InMemoryTourProgressStore()
        try await store.record(TourRecord(tour: .home, version: 1, outcome: .skipped, date: TestTime.now))
        try await store.record(TourRecord(tour: .home, version: 1, outcome: .finished, date: TestTime.now))
        try await store.setShowsTipsOnNewScreens(false)
        let progress = try await store.progress()
        #expect(progress.records[.home]?.outcome == .finished)
        #expect(!progress.showsTipsOnNewScreens)

        try await store.eraseAll()
        #expect(try await store.progress() == .fresh)
    }

    @Test func failsWithTheOtherStores() async {
        let services = FixtureServices.make(
            set: .demo, behavior: .storesFail, now: TestTime.now, calendar: TestTime.calendar)
        await #expect(throws: StoreError.unavailable) { try await services.tours.progress() }
    }
}
