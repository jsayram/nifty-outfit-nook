import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Look detail (Phase 12a): facts, Rename, Wear today, Swap a piece in place, Delete look with
/// Undo, and pieces that left her closet (LR-16.4), on the demo closet.
@MainActor
struct LookDetailModelTests {
    private let us = TestTime.locale

    private func services(_ behavior: FixtureBehavior = .normal) -> NookServices {
        FixtureServices.make(set: .demo, behavior: behavior, now: TestTime.now, calendar: TestTime.calendar)
    }

    private func detail(_ id: Look.ID, services: NookServices? = nil) async -> (LookDetailModel, NookServices) {
        let services = services ?? self.services()
        var next = 0
        let model = LookDetailModel(
            lookID: id, now: { TestTime.now }, calendar: TestTime.calendar,
            makeLookID: {
                next += 1
                return Look.ID("o-new-\(next)")
            })
        await model.load(from: services)
        return (model, services)
    }

    // MARK: Showing

    @Test func showsTheLookAndItsFacts() async throws {
        let (model, _) = await detail("o-interview")
        #expect(model.phase == .loaded)
        #expect(model.name == "Interview navy and pink")
        #expect(model.facts(locale: us) == ["Office", "Saved Sep 4", "Last worn 5 days ago"])
        #expect(try #require(model.content).pieces.count == 4)
        #expect(model.removedPieces.isEmpty)
        #expect(!model.isWornToday)
    }

    /// A suitcase look says where it came from.
    @Test func aSuitcaseLookSaysWhere() async {
        let (model, _) = await detail("o-weekend")
        #expect(model.facts(locale: us) == ["Casual", "Saved Sep 19", "Last worn Sep 24", "From Weekend"])
        #expect(model.sourceName == "Weekend")
    }

    /// An unsaved result, or a look that isn't there, is missing rather than shown.
    @Test func missingLooks() async {
        #expect(await detail("o-history-casual").0.phase == .missing)
        #expect(await detail("o-nothing").0.phase == .missing)
        #expect(await detail("o-interview", services: services(.storesFail)).0.phase == .failed)
    }

    // MARK: Rename

    @Test func renameChecksTheName() async throws {
        let (model, services) = await detail("o-interview")
        #expect(model.renameProblem("") == .empty)
        #expect(model.renameProblem("   ") == .empty)
        #expect(model.renameProblem(String(repeating: "a", count: 61)) == .tooLong(maximum: 60))
        #expect(model.renameProblem("Two\nlines") == .controlCharacters)
        #expect(model.renameProblem("Job interview") == nil)

        await #expect(throws: StoreError.invalidName(.empty)) { try await model.rename(to: " ") }
        try await model.rename(to: "  Job interview  ")
        #expect(model.name == "Job interview")
        #expect(try await services.looks.look("o-interview").name == "Job interview")
    }

    @Test func renameWords() {
        #expect(LookDetailText.nameLine(for: .empty) == "Give the look a name.")
        #expect(LookDetailText.nameLine(for: .tooLong(maximum: 60)) == "Use 60 characters or fewer.")
    }

    // MARK: Wear today

    /// LR-10.1: Wear today sets Last worn on the look and its pieces, and Undo removes it.
    @Test func wearTodayAndUndo() async throws {
        let (model, services) = await detail("o-interview")
        let wear = try await model.wearToday()
        #expect(model.isWornToday)
        #expect(wear.garmentIDs == ["g-navy-cardigan", "g-pink-blouse", "g-navy-trousers", "g-nude-flats"])
        #expect(try await services.looks.look("o-interview").lastWorn == TestTime.now)
        #expect(try await services.closet.garment("g-pink-blouse").lastWorn == TestTime.now)
        #expect(model.facts(locale: us).contains("Last worn today"))

        try await model.undo(wear)
        #expect(!model.isWornToday)
        #expect(try await services.looks.look("o-interview").lastWorn == TestTime.day(-5))
        #expect(try await services.closet.garment("g-pink-blouse").lastWorn != TestTime.now)
    }

    /// Tapping Worn today again takes today off.
    @Test func wornTodayCanBeTakenOff() async throws {
        let (model, _) = await detail("o-interview")
        _ = try await model.wearToday()
        _ = try await model.removeTodaysWear()
        #expect(!model.isWornToday)
    }

    /// A piece she gave away doesn't get the wear.
    @Test func wearSkipsRemovedPieces() async throws {
        let (model, services) = await detail("o-blazer-office")
        let wear = try await model.wearToday()
        #expect(!wear.garmentIDs.contains("g-gray-blazer"))
        #expect(try await services.closet.garment("g-gray-blazer").lastWorn == TestTime.day(-200))
    }

    // MARK: Delete

    /// A stylist's look goes back to history, unsaved and unnamed (LR-06); Undo saves it exactly.
    @Test func deletingAResultUnsavesItAndUndoBringsItBack() async throws {
        let (model, services) = await detail("o-interview")
        let before = try await services.looks.look("o-interview")
        let removal = try await model.delete()
        #expect(model.phase == .missing)
        let after = try await services.looks.look("o-interview")
        #expect(!after.isSaved)
        #expect(after.name == nil)
        #expect(after.savedAt == nil)
        try await removal.undo(in: services.looks)
        #expect(try await services.looks.look("o-interview") == before)
        #expect(removal.name == "Interview navy and pink")
    }

    /// A look she made herself has nowhere else to live, so it's deleted; Undo puts it back.
    @Test func deletingHerOwnLookRemovesItAndUndoBringsItBack() async throws {
        let (model, services) = await detail("o-lace-date")
        let before = try await services.looks.look("o-lace-date")
        let removal = try await model.delete()
        await #expect(throws: StoreError.notFound) { try await services.looks.look("o-lace-date") }
        try await removal.undo(in: services.looks)
        #expect(try await services.looks.look("o-lace-date") == before)
    }

    // MARK: Pieces that left her closet

    /// LR-16.4: the given-away blazer shows faded with a note; a deleted piece says so; a piece
    /// deleted for good is counted.
    @Test func removedPieces() async throws {
        let (model, services) = await detail("o-blazer-office")
        #expect(model.removedPieces.map(\.name) == ["Gray blazer"])
        #expect(model.removedPieces.first?.removal == .noLongerOwned)
        #expect(
            LookDetailText.removedNote(model.removedPieces)
                == "Gray blazer isn’t in your closet any more. Swap it for one of your pieces, or keep the look as it is."
        )

        try await services.closet.delete("g-cream-sweater", at: TestTime.now)
        await model.load(from: services)
        #expect(model.removedPieces.map(\.removal) == [.noLongerOwned, .deleted])
        #expect(model.goneCount == 0)

        // Purged: the store no longer has it.
        let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        model.show(
            looks: data.looks, garments: data.garments.filter { $0.id != "g-navy-trousers" },
            suitcases: data.suitcases, profile: data.profile)
        #expect(model.goneCount == 1)
        #expect(try #require(model.content).pieces.count == 3)
    }

    // MARK: Swap a piece

    /// Swap it starts on the faded piece; using another changes the saved look in place, and Undo
    /// gives back exactly the look before (LR-08.2).
    @Test func swapChangesTheSavedLookInPlace() async throws {
        let (model, services) = await detail("o-blazer-office")
        let before = try #require(model.look)
        let blazer = try #require(before.pieces.first { $0.garmentID == "g-gray-blazer" })
        let swap = try #require(model.swapModel(startingAt: blazer.id))
        #expect(swap.piece?.id == blazer.id)
        #expect(swap.category == .layer)
        #expect(!swap.options.all.contains("g-gray-blazer"))
        let replacement = try #require(swap.options.all.first)
        swap.select(replacement)
        let changed = try #require(swap.swapped())

        let earlier = try await model.applySwap(changed)
        #expect(earlier == before)
        let saved = try await services.looks.look("o-blazer-office")
        #expect(saved.id == before.id)
        #expect(saved.name == before.name)
        #expect(saved.isSaved)
        #expect(saved.savedAt == before.savedAt)
        #expect(saved.wornOn == before.wornOn)
        #expect(saved.garmentIDs.contains(replacement))
        #expect(!saved.garmentIDs.contains("g-gray-blazer"))
        #expect(model.removedPieces.isEmpty)

        try await model.restore(earlier)
        #expect(try await services.looks.look("o-blazer-office") == before)
        #expect(model.look == before)
    }

    /// Swap reads nothing and sends nothing: everything comes from what the detail loaded.
    @Test func swapSetupUsesTheLooksSource() async throws {
        let (weekend, _) = await detail("o-weekend")
        let setup = try #require(weekend.swapSetup())
        #expect(setup.situation.source == .suitcase("s-weekend"))
        #expect(setup.situation.members?.contains("g-olive-trousers") == true)
        #expect(setup.sourceName == "Weekend")
        #expect(!setup.allowsFindOne)
        #expect(setup.situation.weather == nil)

        let (interview, _) = await detail("o-interview")
        let main = try #require(interview.swapSetup())
        #expect(main.situation.source == .mainCloset)
        #expect(main.allowsFindOne)
        #expect(main.layoutSeed == "o-interview")
    }
}
