import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Services

/// The real stores (Phase 21a) pass the same contracts as the in-memory ones
/// (`InMemoryStoreContractTests` in FixturesTests), each on a store file of its own.
struct StoredStoreContractTests {
    @Test(arguments: ClosetStoreContract.Check.allCases)
    func closet(_ check: ClosetStoreContract.Check) async throws {
        let store = try TemporaryStore("closet")
        try await ClosetStoreContract { garments, calendar in
            let closet = StoredClosetStore(container: try store.open().container, calendar: calendar)
            for garment in garments { try await closet.save(garment) }
            return closet
        }.run(check)
    }

    @Test(arguments: LookStoreContract.Check.allCases)
    func looks(_ check: LookStoreContract.Check) async throws {
        let store = try TemporaryStore("looks")
        try await LookStoreContract { looks, calendar in
            let stored = StoredLookStore(container: try store.open().container, calendar: calendar)
            for look in looks { try await stored.save(look) }
            return stored
        }.run(check)
    }

    @Test(arguments: SuitcaseStoreContract.Check.allCases)
    func suitcases(_ check: SuitcaseStoreContract.Check) async throws {
        let store = try TemporaryStore("suitcases")
        try await SuitcaseStoreContract { suitcases in
            let stored = try store.open().suitcases
            for suitcase in suitcases { try await stored.restore(suitcase) }
            return stored
        }.run(check)
    }

    @Test(arguments: ProfileStoreContract.Check.allCases)
    func profile(_ check: ProfileStoreContract.Check) async throws {
        let store = try TemporaryStore("profile")
        try await ProfileStoreContract { profile in
            let stored = try store.open().profile
            try await stored.save(profile)
            return stored
        }.run(check)
    }

    /// The debug sample closet: the sample's profile in memory, with the name and the Style Me
    /// settings kept in the store's profile record.
    @Test(arguments: ProfileStoreContract.Check.allCases)
    func profileWithSettingsKeptInTheStore(_ check: ProfileStoreContract.Check) async throws {
        let store = try TemporaryStore("keeper")
        try await ProfileStoreContract { profile in
            KeptSettingsProfileStore(profile: profile, keeper: try store.open().profileSettings) {
                InMemoryProfileStore(profile: $0)
            }
        }.run(check)
    }

    @Test(arguments: TryOnPictureStoreContract.Check.allCases)
    func pictures(_ check: TryOnPictureStoreContract.Check) async throws {
        let store = try TemporaryStore("pictures")
        try await TryOnPictureStoreContract { pictures in
            let stored = try store.open().pictures
            for picture in pictures { try await stored.save(picture) }
            return stored
        }.run(check)
    }

    @Test(arguments: DraftStoreContract.Check.allCases)
    func drafts(_ check: DraftStoreContract.Check) async throws {
        let store = try TemporaryStore("drafts")
        try await DraftStoreContract { drafts in
            let stored = try store.open().drafts
            for draft in drafts { try await stored.save(draft) }
            return stored
        }.run(check)
    }

    @Test(arguments: LookDraftStoreContract.Check.allCases)
    func lookDrafts(_ check: LookDraftStoreContract.Check) async throws {
        let store = try TemporaryStore("lookDrafts")
        try await LookDraftStoreContract { draft in
            let stored = StoredLookDraftStore(modelContainer: try store.open().container)
            if let draft { try await stored.save(draft) }
            return stored
        }.run(check)
    }

    @Test(arguments: FeedbackDraftStoreContract.Check.allCases)
    func feedbackDrafts(_ check: FeedbackDraftStoreContract.Check) async throws {
        let store = try TemporaryStore("feedback")
        try await FeedbackDraftStoreContract { draft in
            let stored = StoredFeedbackDraftStore(modelContainer: try store.open().container)
            if let draft { try await stored.save(draft) }
            return stored
        }.run(check)
    }

    @Test(arguments: TourProgressStoreContract.Check.allCases)
    func tours(_ check: TourProgressStoreContract.Check) async throws {
        let store = try TemporaryStore("tours")
        try await TourProgressStoreContract { try store.open().tours }.run(check)
    }

    @Test(arguments: OnboardingStateStoreContract.Check.allCases)
    func onboarding(_ check: OnboardingStateStoreContract.Check) async throws {
        let store = try TemporaryStore("onboarding")
        try await OnboardingStateStoreContract { try store.open().onboarding }.run(check)
    }
}
