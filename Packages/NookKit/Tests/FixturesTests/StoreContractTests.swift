import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

/// The store contracts (`NookTestSupport`) run against every in-memory store. Stage B's real
/// stores run the same checks.
struct InMemoryStoreContractTests {
    @Test(arguments: ClosetStoreContract.Check.allCases)
    func closet(_ check: ClosetStoreContract.Check) async throws {
        try await ClosetStoreContract { InMemoryClosetStore(garments: $0, calendar: $1) }.run(check)
    }

    @Test(arguments: LookStoreContract.Check.allCases)
    func looks(_ check: LookStoreContract.Check) async throws {
        try await LookStoreContract { InMemoryLookStore(looks: $0, calendar: $1) }.run(check)
    }

    @Test(arguments: SuitcaseStoreContract.Check.allCases)
    func suitcases(_ check: SuitcaseStoreContract.Check) async throws {
        try await SuitcaseStoreContract { InMemorySuitcaseStore(suitcases: $0) }.run(check)
    }

    @Test(arguments: ProfileStoreContract.Check.allCases)
    func profile(_ check: ProfileStoreContract.Check) async throws {
        try await ProfileStoreContract { InMemoryProfileStore(profile: $0) }.run(check)
    }

    /// The profile with the name on the sign and the Style Me settings kept across launches
    /// (Stage A audit), in front of the in-memory store.
    @Test(arguments: ProfileStoreContract.Check.allCases)
    func profileWithKeptSettings(_ check: ProfileStoreContract.Check) async throws {
        try await ProfileStoreContract {
            KeptSettingsProfileStore(profile: $0, keeper: InMemoryProfileSettingsKeeper()) {
                InMemoryProfileStore(profile: $0)
            }
        }.run(check)
    }

    @Test(arguments: TryOnPictureStoreContract.Check.allCases)
    func pictures(_ check: TryOnPictureStoreContract.Check) async throws {
        try await TryOnPictureStoreContract { InMemoryTryOnPictureStore(pictures: $0) }.run(check)
    }

    @Test(arguments: DraftStoreContract.Check.allCases)
    func drafts(_ check: DraftStoreContract.Check) async throws {
        try await DraftStoreContract { InMemoryDraftStore(drafts: $0) }.run(check)
    }

    @Test(arguments: LookDraftStoreContract.Check.allCases)
    func lookDrafts(_ check: LookDraftStoreContract.Check) async throws {
        try await LookDraftStoreContract { InMemoryLookDraftStore(draft: $0) }.run(check)
    }

    @Test(arguments: TourProgressStoreContract.Check.allCases)
    func tours(_ check: TourProgressStoreContract.Check) async throws {
        try await TourProgressStoreContract { InMemoryTourProgressStore() }.run(check)
    }

    @Test(arguments: OnboardingStateStoreContract.Check.allCases)
    func onboarding(_ check: OnboardingStateStoreContract.Check) async throws {
        try await OnboardingStateStoreContract { InMemoryOnboardingStore() }.run(check)
    }

    /// A failing store fails every call with `unavailable` and changes nothing, so a screen shows
    /// its error state. Checked on the look draft store, which had no tests of its own.
    @Test func aFailingLookDraftStoreChangesNothing() async throws {
        let draft = LookDraft(name: "Rainy office", savedAt: TestTime.now)
        let store = InMemoryLookDraftStore(draft: draft, options: StoreOptions(fails: true))
        await #expect(throws: StoreError.unavailable) { try await store.draft() }
        await #expect(throws: StoreError.unavailable) { try await store.save(LookDraft(savedAt: TestTime.now)) }
        await #expect(throws: StoreError.unavailable) { try await store.discard() }
        await #expect(throws: StoreError.unavailable) { try await store.eraseAll() }
    }
}
