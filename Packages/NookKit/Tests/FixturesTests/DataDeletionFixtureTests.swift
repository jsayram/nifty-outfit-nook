import Fixtures
import Foundation
import Models
import Testing

/// Delete my data over the real Stage A stores (Phase 14b): after it, every store reads as a
/// fresh install, and nothing from before comes back.
struct DataDeletionFixtureTests {
    private func services(
        _ set: FixtureSet = .demo, behavior: FixtureBehavior = .normal, draft: FixtureDraftState? = nil
    ) -> NookServices {
        FixtureServices.make(
            set: set, behavior: behavior, draft: draft, now: TestTime.now, calendar: TestTime.calendar)
    }

    @Test func deletionWipesEveryStore() async throws {
        let services = services(draft: .look)
        // Something in every store first, including an add draft beside the look draft.
        try await services.drafts.save(
            GarmentDraft(
                target: .newPiece, step: .details, details: GarmentDetails(name: "Sage cardigan"),
                base: GarmentDetails(), savedAt: TestTime.now))
        #expect(try await !services.closet.garments().isEmpty)
        #expect(try await !services.looks.looks().isEmpty)
        #expect(try await !services.pictures.pictures().isEmpty)
        #expect(try await !services.suitcases.suitcases().isEmpty)
        #expect(try await services.profile.profile() != Profile())
        #expect(try await !services.drafts.drafts().isEmpty)
        #expect(try await services.lookDrafts.draft() != nil)

        let report = await services.deletion.delete(.thisDevice)

        #expect(report.isComplete)
        #expect(Set(report.order) == Set(DataPart.allCases))
        #expect(try await services.closet.garments().isEmpty)
        #expect(try await services.looks.looks().isEmpty)
        #expect(try await services.pictures.pictures().isEmpty)
        #expect(try await services.suitcases.suitcases().isEmpty)
        #expect(try await services.drafts.drafts().isEmpty)
        #expect(try await services.lookDrafts.draft() == nil)
        // The profile is a fresh one: no name, the default Preferences (tracking off), no
        // measurements, fitting pieces or photo, and the main closet as the source.
        let profile = try await services.profile.profile()
        #expect(profile == Profile())
        #expect(profile.signName.isEmpty)
        #expect(profile.preferences == Preferences())
        #expect(profile.measurements.isEmpty)
        #expect(profile.tryOnPhoto == nil)
        #expect(profile.remembered == RememberedChoices())
    }

    @Test func afterDeletingTheStoresMatchTheEmptySet() async throws {
        // A fresh install is `-fixtures empty`; deleting the demo must read the same.
        let deleted = services()
        _ = await deleted.deletion.delete(.thisDevice)
        let empty = services(.empty)
        #expect(try await deleted.closet.garments() == empty.closet.garments())
        #expect(try await deleted.looks.looks() == empty.looks.looks())
        #expect(try await deleted.suitcases.suitcases() == empty.suitcases.suitcases())
        #expect(try await deleted.profile.profile() == empty.profile.profile())
    }

    @Test func deletingTwiceIsSafe() async {
        let services = services()
        #expect(await services.deletion.delete(.thisDevice).isComplete)
        #expect(await services.deletion.delete(.thisDevice).isComplete)
    }

    @Test func failingStoresReportEveryPart() async {
        let report = await services(behavior: .storesFail).deletion.delete(.thisDevice)
        #expect(!report.isComplete)
        #expect(Set(report.failedParts) == Set(DataPart.allCases))
    }

    @Test func theLargeClosetIsWipedToo() async throws {
        let services = services(.large)
        #expect(try await services.closet.garments().count > 2000)
        #expect(await services.deletion.delete(.thisDevice).isComplete)
        #expect(try await services.closet.garments().isEmpty)
        #expect(try await services.looks.looks().isEmpty)
    }
}
