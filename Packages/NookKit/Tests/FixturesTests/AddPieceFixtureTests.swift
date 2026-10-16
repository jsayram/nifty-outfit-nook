import Foundation
import Models
import NookTestSupport
import Testing

@testable import Fixtures

/// Describe in words (Phase 7b): the on-phone word matcher. It only names what she said; it
/// has no style rules.
struct WordMatchDescriptionReaderTests {
    private func suggestions(_ text: String) -> [GarmentSuggestion] {
        WordMatchDescriptionReader.suggestions(for: text)
    }

    @Test func theMockupsCardigan() {
        #expect(
            suggestions("Sage green cardigan with gold buttons, soft and cozy") == [
                .name("Sage cardigan"), .category(.layer), .colors([.green], note: "Sage"), .warmth(.warm),
                .detail("Gold buttons"),
            ])
    }

    @Test func theLastKindWordNamesThePiece() {
        // "Dress shoes" are shoes, a "sweater dress" is a dress, "dress pants" are bottoms.
        #expect(suggestions("black dress shoes").contains(.category(.shoes)))
        #expect(suggestions("grey sweater dress").contains(.category(.dress)))
        #expect(suggestions("navy dress pants").contains(.category(.bottom)))
        #expect(suggestions("navy dress pants").first == .name("Navy pants"))
    }

    @Test func pluralsAndHyphensAreKinds() {
        #expect(suggestions("white t-shirt").contains(.category(.top)))
        #expect(suggestions("comfy joggers").contains(.category(.bottom)))
        #expect(suggestions("tan loafer").contains(.category(.shoes)))
    }

    @Test func coloursKeepTheirOrderAndShades() {
        #expect(suggestions("black and white striped top").contains(.colors([.black, .white], note: nil)))
        #expect(suggestions("light pink blouse").contains(.colors([.pink], note: "Light pink")))
        #expect(suggestions("light pink blouse").first == .name("Light pink blouse"))
        #expect(suggestions("Dusty rose skirt").contains(.colors([.pink], note: "Dusty rose")))
        #expect(suggestions("charcoal coat").contains(.colors([.gray], note: "Charcoal")))
    }

    @Test func lightBeforeAColourIsAShadeNotWarmth() {
        #expect(!suggestions("light pink blouse").contains(.warmth(.light)))
        #expect(suggestions("light linen shirt").contains(.warmth(.light)))
    }

    @Test func cutDressinessSeasonsAndOccasions() {
        let found = suggestions("Relaxed silk blouse for date night or the office, summer and spring")
        #expect(found.contains(.fit(.relaxed)))
        #expect(found.contains(.dressiness(.dressy)))
        #expect(found.contains(.seasons([.summer, .spring])))
        #expect(found.contains(.occasions([.dateNight, .office])))
    }

    @Test func aBrandAfterFromOrBy() {
        #expect(suggestions("Light pink silk blouse from Old Navy").contains(.brand("Old Navy")))
        #expect(suggestions("jeans by Levi's").contains(.brand("Levi's")))
        // Lower-case words after "by" aren't a brand.
        #expect(!suggestions("skirt I wear by the beach").contains { if case .brand = $0 { true } else { false } })
    }

    @Test func theBrandIsntReadAsAColour() {
        let found = suggestions("Light pink silk blouse from Old Navy with a bow at the neck")
        #expect(found.contains(.colors([.pink], note: "Light pink")))
        #expect(found.contains(.detail("A bow at the neck")))
    }

    @Test func caseAndAccentsDontMatter() {
        #expect(suggestions("BLUSH Cardigan").contains(.category(.layer)))
        #expect(suggestions("BLUSH Cardigan").contains(.colors([.pink], note: "Blush")))
        #expect(suggestions("crème coat").contains(.colors([.cream], note: "Crème")))
    }

    @Test func nothingRecognisedGivesNothing() {
        #expect(suggestions("").isEmpty)
        #expect(suggestions("my favourite thing").isEmpty)
    }

    @Test func noKindMeansNoName() {
        let found = suggestions("something navy and cozy")
        #expect(!found.contains { if case .name = $0 { true } else { false } })
        #expect(found.contains(.colors([.navy], note: nil)))
    }

    @Test func itIsTheSameEveryTime() async throws {
        let reader = WordMatchDescriptionReader()
        let text = "Sage green cardigan with gold buttons, soft and cozy"
        let first = try await reader.suggestions(for: text)
        let second = try await reader.suggestions(for: text)
        #expect(first == second)
    }
}

struct InMemoryDraftStoreTests {
    private func draft(_ target: GarmentDraft.Target, name: String, at offset: TimeInterval) -> GarmentDraft {
        GarmentDraft(
            target: target, step: .details, details: GarmentDetails(name: name), base: .blank,
            savedAt: TestTime.now.addingTimeInterval(offset))
    }

    @Test func savesOneDraftPerTarget() async throws {
        let store = InMemoryDraftStore()
        try await store.save(draft(.newPiece, name: "First", at: 0))
        try await store.save(draft(.newPiece, name: "Second", at: 10))
        try await store.save(draft(.garment("g-1"), name: "Edit", at: 5))
        let drafts = try await store.drafts()
        #expect(drafts.map(\.details.name) == ["Second", "Edit"])
        #expect(try await store.draft(for: .newPiece)?.details.name == "Second")
        #expect(try await store.draft(for: .garment("g-2")) == nil)
    }

    @Test func discardRemovesOnlyThatTarget() async throws {
        let store = InMemoryDraftStore(drafts: [
            draft(.newPiece, name: "A", at: 0), draft(.garment("g-1"), name: "B", at: 0),
        ])
        try await store.discard(.newPiece)
        try await store.discard(.newPiece)
        #expect(try await store.drafts().map(\.target) == [.garment("g-1")])
    }

    @Test func failsLikeTheOtherStores() async {
        let store = InMemoryDraftStore(options: StoreOptions(fails: true))
        await #expect(throws: StoreError.unavailable) { try await store.drafts() }
    }
}

struct AddPieceFixtureTests {
    @Test func thePhotoStandInGivesASamplePicture() async throws {
        for source in PhotoSource.allCases {
            #expect(try await StandInPhotoIntake().photo(from: source) == StandInPhotoIntake.samplePhoto)
        }
        await #expect(throws: PhotoIntakeError.unreadable) {
            try await StandInPhotoIntake(fails: true).photo(from: .camera)
        }
    }

    @Test(arguments: FixtureDraftState.allCases)
    func readsEachDraft(_ draft: FixtureDraftState) {
        let configuration = FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo:draft=\(draft.rawValue)"])
        #expect(configuration == FixtureConfiguration(set: .demo, draft: draft))
    }

    @Test func theAddDraftIsTheDescribedCardigan() async throws {
        let services = FixtureServices.make(set: .demo, draft: .add, now: TestTime.now, calendar: TestTime.calendar)
        let draft = try #require(try await services.drafts.draft(for: .newPiece))
        #expect(draft.step == .details)
        #expect(draft.details.name == "Sage cardigan")
        #expect(draft.details.category == .layer)
        #expect(draft.description == FixtureDrafts.addDescription)
        #expect(draft.hasChanges)
        #expect(draft.savedAt == TestTime.now.addingTimeInterval(-300))
    }

    @Test func theEditDraftRenamesTheTrousers() async throws {
        let services = FixtureServices.make(set: .demo, draft: .edit, now: TestTime.now, calendar: TestTime.calendar)
        let draft = try #require(try await services.drafts.draft(for: .garment("g-navy-trousers")))
        #expect(draft.base.name == "Navy dress pants")
        #expect(draft.details.name == "Navy work trousers")
        #expect(draft.hasChanges)
        // The empty set has no trousers, so no edit draft.
        let empty = FixtureServices.make(set: .empty, draft: .edit, now: TestTime.now, calendar: TestTime.calendar)
        #expect(try await empty.drafts.drafts().isEmpty)
    }

    @Test func noDraftUnlessAsked() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        #expect(try await services.drafts.drafts().isEmpty)
    }

    @Test func photoFailsReachesThePhotoStep() async {
        let services = FixtureServices.make(
            set: .demo, behavior: .photoFails, now: TestTime.now, calendar: TestTime.calendar)
        await #expect(throws: PhotoIntakeError.unreadable) { try await services.photos.photo(from: .library) }
    }

    @Test func theClosetStoreChecksTheOtherFields() async throws {
        let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        let store = InMemoryClosetStore(garments: data.garments, calendar: TestTime.calendar)
        var garment = try await store.garment("g-black-tee")
        garment.brand = String(repeating: "b", count: 41)
        await #expect(throws: StoreError.invalidDetails(GarmentProblems([.brand: .tooLong(maximum: 40)]))) {
            try await store.save(garment)
        }
    }

    @Test(arguments: FixtureSet.allCases)
    func everyFixtureGarmentPassesTheChecks(_ set: FixtureSet) {
        let data = set.data(now: TestTime.now, calendar: TestTime.calendar)
        #expect(data.garments.allSatisfy { GarmentRules.problems(in: $0).isEmpty })
    }
}
