import Foundation
import Models
import NookTestSupport
import Testing

@testable import Fixtures

/// Phase 21a: with the real stores passed in, the services keep her data there and nothing from
/// the sample set, while the providers still follow the configuration.
struct RealStoresFixtureTests {
    private func stores() -> NookStoreSet {
        NookStoreSet(
            closet: InMemoryClosetStore(garments: [], calendar: TestTime.calendar),
            looks: InMemoryLookStore(looks: [], calendar: TestTime.calendar),
            suitcases: InMemorySuitcaseStore(suitcases: []),
            profile: InMemoryProfileStore(profile: Profile(signName: "Kept")),
            drafts: InMemoryDraftStore(), lookDrafts: InMemoryLookDraftStore(),
            pictures: InMemoryTryOnPictureStore(pictures: []), feedbackDrafts: InMemoryFeedbackDraftStore())
    }

    @Test func theStoresPassedInHoldHerData() async throws {
        let stores = stores()
        let services = FixtureServices.make(
            FixtureConfiguration(set: .demo, draft: .add), startingCloset: .empty, stores: stores, now: TestTime.now,
            calendar: TestTime.calendar)
        #expect(services.keepsChanges)
        #expect(try await services.closet.garments().isEmpty)
        #expect(try await services.drafts.drafts().isEmpty)
        #expect(try await services.profile.profile().signName == "Kept")
        try await services.feedbackDrafts.save(FeedbackDraft(message: "Hi"))
        #expect(try await stores.feedbackDrafts.draft()?.message == "Hi")
    }

    @Test func sampleDataInMemoryIsNotKept() {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        #expect(!services.keepsChanges)
    }
}
