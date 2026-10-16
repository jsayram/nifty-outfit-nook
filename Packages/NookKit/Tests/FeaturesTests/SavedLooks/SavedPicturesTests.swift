import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// The Pictures tab, picture detail, and the links between pictures and looks (Phase 12b,
/// RD-08), on the demo closet: two pictures of Interview navy and pink (the older one of an
/// earlier version) and one of Lace date night.
@MainActor
struct SavedPicturesTests {
    private let us = ClosetTestTime.locale

    private func services(_ behavior: FixtureBehavior = .normal) -> NookServices {
        FixtureServices.make(set: .demo, behavior: behavior, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
    }

    private func ids(_ model: SavedLooksModel) -> [String] {
        model.shownPictures.map(\.id.rawValue)
    }

    private func picture(_ id: TryOnPicture.ID, services: NookServices) async -> PictureDetailModel {
        let model = PictureDetailModel(pictureID: id, now: { ClosetTestTime.now }, calendar: ClosetTestTime.calendar)
        await model.load(from: services)
        return model
    }

    private func look(_ id: Look.ID, services: NookServices) async -> LookDetailModel {
        let model = LookDetailModel(lookID: id, now: { ClosetTestTime.now }, calendar: ClosetTestTime.calendar)
        await model.load(from: services)
        return model
    }

    // MARK: The Pictures tab

    @Test func picturesNewestFirstWithTheirLooks() async throws {
        let model = await loadedSavedLooks()
        #expect(model.picturesPhase == .loaded)
        #expect(ids(model) == ["p-interview", "p-interview-earlier", "p-lace"])
        #expect(model.picturesCountText == "3 pictures")
        #expect(!model.hasNoPictures)
        let earlier = try #require(model.pictureItem("p-interview-earlier"))
        #expect(earlier.lookName == "Interview navy and pink")
        #expect(earlier.look?.id == "o-interview")
        guard case .changed = earlier.status else {
            Issue.record("The earlier picture should show an earlier version, not \(earlier.status)")
            return
        }
        // It shows the pieces it was made with: the cream sweater, not today's pink shirt.
        #expect(earlier.content.pieces.map(\.name).contains("Cream knit sweater"))
        #expect(!earlier.content.pieces.map(\.name).contains("Cute pink shirt"))
    }

    @Test func noPicturesYet() async {
        let model = await loadedSavedLooks(.empty)
        #expect(model.hasNoPictures)
        #expect(model.picturesCountText == "")
    }

    /// A picture store that can't be read fails the Pictures tab only.
    @Test func failingStoresShowTheErrorState() async {
        let model = await loadedSavedLooks(behavior: .storesFail)
        #expect(model.picturesPhase == .failed)
    }

    /// RD-08.3: search on Pictures finds a picture by its look's name, occasion and pieces, and
    /// the chips match the pieces the picture shows.
    @Test func searchAndFiltersMatchTheLookAPictureCameFrom() async {
        let model = await loadedSavedLooks(searchDelay: .zero)
        model.tab = .pictures
        for (query, expected) in [
            ("interview", ["p-interview", "p-interview-earlier"]),
            ("date night", ["p-lace"]),
            ("cream sweater", ["p-interview-earlier"]),
            ("navy cardigan", ["p-interview", "p-interview-earlier"]),
            ("weekend", []),
        ] {
            model.searchText = query
            await model.settleSearch()
            #expect(ids(model) == expected, "\(query)")
        }
        model.clearFilters()
        model.toggle(.bag)
        #expect(ids(model) == ["p-lace"])
        #expect(model.picturesCountText == "1 of 3 pictures")
        model.toggle(.burgundy)
        model.toggle(.bag)
        model.toggle(.dress)
        #expect(model.picturesHaveNoMatches)
        #expect(model.filterSummary == "Dresses · Burgundy")
    }

    @Test func oneIsSingular() async {
        let model = await loadedSavedLooks(searchDelay: .zero)
        model.searchText = "lace"
        await model.settleSearch()
        #expect(model.picturesCountText == "1 of 3 pictures")
        #expect(TryOnText.pictures(1) == "1 picture")
    }

    // MARK: Picture detail

    @Test func detailShowsThePictureAndItsLook() async {
        let model = await picture("p-interview", services: services())
        #expect(model.phase == .loaded)
        #expect(model.facts(locale: us) == "Simulated · Made Sep 6")
        #expect(model.look?.id == "o-interview")
        #expect(model.linkNote == nil)
        let earlier = await picture("p-interview-earlier", services: services())
        #expect(earlier.linkNote == TryOnText.earlierVersion)
        #expect(await picture("p-nothing", services: services()).phase == .missing)
        #expect(await picture("p-lace", services: services(.storesFail)).phase == .failed)
    }

    /// Delete picture removes only the picture, and Undo brings it back linked to its look.
    @Test func deletePictureWithUndo() async throws {
        let services = services()
        let detail = await picture("p-lace", services: services)
        let removal = try await detail.delete()
        #expect(detail.phase == .missing)
        #expect(try await services.pictures.pictures().map(\.id) == ["p-interview", "p-interview-earlier"])
        // The look is untouched and no longer lists the picture.
        let lace = await look("o-lace-date", services: services)
        #expect(lace.phase == .loaded)
        #expect(lace.pictures.isEmpty)

        let grid = await loadedSavedLooks()
        grid.lastPictureRemoval = removal
        await grid.load(from: services, now: ClosetTestTime.now)
        await grid.undoLastPictureRemoval(using: services, now: ClosetTestTime.now)
        #expect(grid.lastPictureRemoval == nil)
        #expect(ids(grid) == ["p-interview", "p-interview-earlier", "p-lace"])
        await lace.load(from: services)
        #expect(lace.pictures.map(\.id) == ["p-lace"])
    }

    // MARK: Look detail and link integrity

    /// RD-08.2: the look shows its pictures, newest first, and which show an earlier version.
    @Test func aLookShowsItsPictures() async throws {
        let model = await look("o-interview", services: services())
        #expect(model.pictures.map(\.id) == ["p-interview", "p-interview-earlier"])
        let earlier = try #require(model.pictures.last)
        #expect(model.isEarlierVersion(earlier))
        #expect(model.pictureFacts(earlier, locale: us) == "Simulated · Made Sep 5 · Earlier version")
        #expect(await look("o-blazer-office", services: services()).pictures.isEmpty)
    }

    /// Deleting a look keeps its pictures (PRD §7.5, §9.2.4), says so, and Undo links them again.
    @Test func deletingALookKeepsItsPictures() async throws {
        let services = services()
        let detail = await look("o-lace-date", services: services)
        let removal = try await detail.delete()
        #expect(removal.pictureCount == 1)
        #expect(LookDetailText.deleted(removal) == "Deleted Lace date night. Its picture stays in Pictures.")

        let picture = await picture("p-lace", services: services)
        #expect(picture.phase == .loaded)
        #expect(picture.look == nil)
        #expect(picture.linkNote == TryOnText.lookNotSaved)
        // Search still finds it by the name it had.
        let grid = await loadedSavedLooksFrom(services, searchDelay: .zero)
        #expect(grid.pictureItem("p-lace")?.lookName == "Lace date night")
        grid.searchText = "lace"
        await grid.settleSearch()
        #expect(ids(grid) == ["p-lace"])

        try await removal.undo(in: services.looks)
        await picture.load(from: services)
        #expect(picture.look?.id == "o-lace-date")
        #expect(picture.linkNote == nil)
    }

    @Test func deletingALookWithTwoPicturesSaysHowMany() async throws {
        let detail = await look("o-interview", services: services())
        let removal = try await detail.delete()
        #expect(
            LookDetailText.deleted(removal) == "Deleted Interview navy and pink. Its 2 pictures stay in Pictures.")
        #expect(LookDetailText.deleted(SavedLookRemoval(look: removal.look)) == "Deleted Interview navy and pink")
    }

    /// A swap on the look changes it in place: its pictures stay linked, now as earlier versions.
    @Test func swappingALookMakesItsPicturesEarlierVersions() async throws {
        let services = services()
        let detail = await look("o-lace-date", services: services)
        var changed = try #require(detail.look)
        changed.pieces[0] = LookPiece(id: "o-lace-date-g-cream-crop", content: .garment("g-cream-crop"))
        _ = try await detail.applySwap(changed)
        let picture = await picture("p-lace", services: services)
        #expect(picture.look?.id == "o-lace-date")
        #expect(picture.linkNote == TryOnText.earlierVersion)
    }

    // MARK: Speed

    /// The large set's 165 pictures load and filter as fast as its looks.
    @Test(.heavyMainActorWork) func largeSetStaysQuick() async throws {
        let data = FixtureSet.large.data(now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
        let model = SavedLooksModel(searchDelay: .zero)
        model.show(data.looks, garments: data.garments, now: ClosetTestTime.now)
        let loading = SpeedCheck.fastest {
            model.showPictures(data.pictures)
        }
        #expect(model.pictureItems.count > 150)
        #expect(loading < SpeedCheck.limit(.milliseconds(250)), "Loading took \(loading)")
        let filtering = SpeedCheck.fastest {
            model.toggle(.bottom)
            model.toggle(.black)
            model.applySearchNow()
            model.clearFilters()
        }
        #expect(filtering < SpeedCheck.limit(.milliseconds(250)), "Filtering took \(filtering)")
    }
}

/// A Saved Looks model loaded from services a test already changed.
@MainActor
func loadedSavedLooksFrom(_ services: NookServices, searchDelay: Duration = .milliseconds(250)) async
    -> SavedLooksModel
{
    let model = SavedLooksModel(searchDelay: searchDelay)
    await model.load(from: services, now: ClosetTestTime.now)
    return model
}
