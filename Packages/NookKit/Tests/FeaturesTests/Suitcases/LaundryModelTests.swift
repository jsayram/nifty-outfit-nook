import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// Laundry (Phase 13, RD-11, PRD §7.3): what's listed, the scopes, and cleaning with Undo.
@MainActor
struct LaundryModelTests {
    private let now = ClosetTestTime.now

    private func services(laundry: FixtureLaundryState? = .some, source: FixtureSourceState? = nil) -> NookServices {
        FixtureServices.make(set: .demo, laundry: laundry, source: source, now: now, calendar: ClosetTestTime.calendar)
    }

    private func loaded(_ services: NookServices) async -> LaundryModel {
        let model = LaundryModel()
        await model.load(from: services)
        return model
    }

    @Test func listsTheDirtyPieces() async {
        let model = await loaded(services())
        #expect(model.phase == .loaded)
        #expect(model.tracksLaundry)
        #expect(Set(model.shown.map(\.id)) == ["g-lace-top", "g-black-tee"])
        #expect(model.sourceSuitcase == nil)
        let tee = model.shown.first { $0.id == "g-black-tee" }
        #expect(tee.map { model.whereItIs($0, locale: ClosetTestTime.locale) } == "packed in Gym and Weekend")
    }

    @Test func trackingOffKeepsTheMarksAndTurnOnBringsThemBack() async {
        // RD-11.2, RD-11.4
        let services = services(laundry: nil)
        let model = await loaded(services)
        #expect(!model.tracksLaundry)
        #expect(model.dirtyCount == 2)
        #expect(await model.turnOnTracking(in: services))
        #expect(model.tracksLaundry)
        #expect(model.shown.count == 2)
    }

    @Test func aSuitcaseSourceAddsItsScope() async {
        let model = await loaded(services(source: .suitcase))
        #expect(model.sourceSuitcase?.name == "Jose's house")
        #expect(model.count(in: .mainCloset) == 2)
        #expect(model.count(in: .suitcase("s-jose")) == 1)
        model.toggleSelected("g-black-tee")
        model.choose(scope: .suitcase("s-jose"))
        #expect(model.selected.isEmpty)
        #expect(model.shown.map(\.id) == ["g-lace-top"])
        #expect(model.scopeName == "Jose's house")
    }

    @Test func markOneCleanThenUndo() async throws {
        let services = services()
        let model = await loaded(services)
        let cleaned = try await model.markClean(["g-black-tee"], in: services)
        #expect(cleaned == ["g-black-tee"])
        #expect(model.shown.map(\.id) == ["g-lace-top"])
        #expect(try await services.closet.garment("g-black-tee").laundry == .clean)
        try await model.undoClean(cleaned, in: services)
        #expect(model.shown.count == 2)
    }

    @Test func markSelectedAndAllClean() async throws {
        let services = services(laundry: .full)
        let model = await loaded(services)
        #expect(model.shown.count == 8)
        let two = Array(model.shown.prefix(2).map(\.id))
        two.forEach(model.toggleSelected)
        #expect(model.selected.count == 2)
        let cleaned = try await model.markClean(two, in: services)
        #expect(cleaned.count == 2)
        #expect(model.selected.isEmpty)
        #expect(model.shown.count == 6)
        let rest = try await model.markClean(model.shown.map(\.id), in: services)
        #expect(rest.count == 6)
        #expect(model.shown.isEmpty)
        // The hamper on Home follows (RD-11.3).
        let home = HomeModel()
        await home.load(from: services)
        #expect(home.content.hamper == .allClean)
    }

    @Test func undoLeavesAPieceMarkedDirtyAgain() async throws {
        let services = services()
        let model = await loaded(services)
        let cleaned = try await model.markClean(["g-black-tee", "g-lace-top"], in: services)
        // Marked dirty again on its detail before Undo: Undo leaves it be, and puts the other back.
        try await services.closet.setLaundry(.dirty, for: ["g-black-tee"])
        try await services.closet.update("g-lace-top") { $0.ownership = .noLongerOwned }
        try await model.undoClean(cleaned, in: services)
        #expect(try await services.closet.garment("g-lace-top").laundry == .clean)
        #expect(model.shown.map(\.id) == ["g-black-tee"])
    }

    /// RD-11.5: Style Me leaves out a piece in the wash while tracking is on, and uses it once
    /// it's clean.
    @Test func styleMeLeavesOutPiecesInTheWash() async throws {
        let services = services()
        let before = StyleMeModel()
        await before.load(from: services, now: now)
        #expect(!before.startingPieceChoices.contains { $0.id == "g-black-tee" })
        let model = await loaded(services)
        _ = try await model.markClean(["g-black-tee"], in: services)
        let after = StyleMeModel()
        await after.load(from: services, now: now)
        #expect(after.startingPieceChoices.contains { $0.id == "g-black-tee" })
    }

    @Test func words() {
        #expect(LaundryText.inTheWash(0) == "Nothing in the wash")
        #expect(LaundryText.inTheWash(1) == "1 piece in the wash")
        #expect(LaundryText.inTheWash(3) == "3 pieces in the wash")
        #expect(LaundryText.markedClean(["Black tee"]) == "Black tee marked clean")
        #expect(LaundryText.markedClean(["a", "b"]) == "2 pieces marked clean")
    }
}
