import Fixtures
import Foundation
import Models
import NookTestSupport
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

    /// Reset all tips in App tours (Phase 16b): every tour unseen, the switch as she left it.
    @Test func forgettingSeenToursKeepsTheSwitch() async throws {
        let store = InMemoryTourProgressStore()
        try await store.record(TourRecord(tour: .closet, version: 1, outcome: .skipped, date: TestTime.now))
        try await store.setShowsTipsOnNewScreens(false)
        try await store.forgetSeenTours()
        let progress = try await store.progress()
        #expect(progress.records.isEmpty)
        #expect(!progress.showsTipsOnNewScreens)
    }

    @Test func failsWithTheOtherStores() async {
        let services = FixtureServices.make(
            set: .demo, behavior: .storesFail, now: TestTime.now, calendar: TestTime.calendar)
        await #expect(throws: StoreError.unavailable) { try await services.tours.progress() }
    }
}
