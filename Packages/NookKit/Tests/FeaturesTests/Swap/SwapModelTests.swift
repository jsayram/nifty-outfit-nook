import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// A Your looks model with numbered look IDs for swaps (edit-1, edit-2, …), styled and settled.
@MainActor
func swappableLooks(
    _ request: StyleRequest = lookRequest(), services: NookServices = yourLooksServices()
) async -> YourLooksModel {
    var next = 0
    let model = YourLooksModel(
        request: request, now: { ClosetTestTime.now }, calendar: ClosetTestTime.calendar,
        makeLookID: {
            next += 1
            return Look.ID("edit-\(next)")
        })
    model.start(with: services)
    await model.settle()
    return model
}

/// Swap a piece (LR-07, LR-08) on the demo's Office result: Simple is the navy cardigan, cream
/// knit sweater, olive trousers and tan loafers, on a rainy 14.5° day.
@MainActor
struct SwapModelTests {
    private func swap(_ model: YourLooksModel, on category: GarmentCategory? = nil) throws -> SwapModel {
        let swap = try #require(model.swapModel(sourceName: "Main closet"))
        if let category, let piece = swap.pieces.first(where: { swap.category(of: $0) == category }) {
            swap.choosePiece(piece.id)
        }
        return swap
    }

    // MARK: Options

    /// LR-07.1: opening Swap, choosing a piece, Show 3 more and trying one send nothing.
    @Test func swappingSendsNothing() async throws {
        let stylist = ScriptedStylist()
        let model = await swappableLooks(services: yourLooksServices(stylist: stylist))
        let swap = try swap(model)
        for piece in swap.pieces { swap.choosePiece(piece.id) }
        swap.showMore()
        if let first = swap.visibleOptions.first { swap.select(first) }
        _ = swap.seeAllScope
        #expect(await stylist.calls == 1)
        #expect(model.requestsSent == 1)
    }

    /// It opens on the first main piece, the top, with the line above the options.
    @Test func opensOnTheTop() async throws {
        let swap = try swap(await swappableLooks())
        #expect(swap.category == .top)
        #expect(swap.piece?.garmentID == "g-cream-sweater")
        #expect(swap.pieces.compactMap { swap.category(of: $0) } == [.layer, .top, .bottom, .shoes])
        let text = SwapText(category: swap.category, sourceName: "Main closet")
        #expect(text.explanation == "Your tops that go with this look")
        #expect(text.everyOne == "That’s every top in Main closet.")
        #expect(text.seeAll == "See all tops")
        #expect(text.use == "Use this top")
        #expect(
            SwapText(category: .shoes, sourceName: "Jose's house").everyOne
                == "That’s every pair of shoes in Jose's house.")
        #expect(SwapText(category: .shoes, sourceName: "").use == "Use these shoes")
    }

    /// Options are her pieces of the same kind she can wear today, never the ones in the look.
    @Test func optionsAreHerPiecesOfTheSameKind() async throws {
        let model = await swappableLooks()
        let swap = try swap(model, on: .shoes)
        #expect(swap.options.ranked == ["g-black-heels", "g-nude-flats"])
        #expect(swap.options.weaker == ["g-white-sneakers"])
        let all = swap.options.all
        #expect(all.allSatisfy { model.garments[$0]?.category == .shoes })
        #expect(!all.contains("g-tan-loafers"))
    }

    /// LR-07.2: from a suitcase, only what's packed.
    @Test func optionsComeFromTheSuitcase() async throws {
        let model = await swappableLooks(lookRequest(source: .suitcase("s-weekend"), occasion: .casual))
        let members = try #require(model.suitcases.first { $0.id == "s-weekend" }).garmentIDs
        let swap = try swap(model)
        for piece in swap.pieces {
            swap.choosePiece(piece.id)
            #expect(swap.options.all.allSatisfy(members.contains), "\(piece.id)")
        }
    }

    /// LR-10: Dressed up's trousers would rebuild the outfit she wore 5 days ago, so they're only
    /// in See all, marked.
    @Test func anOutfitWornRecentlyIsOnlyInSeeAll() async throws {
        let model = await swappableLooks()
        model.version = .dressedUp
        let swap = try swap(model, on: .bottom)
        #expect(!swap.options.ranked.contains("g-navy-trousers"))
        #expect(swap.options.wornRecently["g-navy-trousers"] == ClosetTestTime.day(-5))
        #expect(swap.seeAllScope.notes["g-navy-trousers"] == SwapText.wornTogether)
    }

    /// LR-07.3: See all lists every option of the kind, good matches first, weaker ones marked.
    @Test func seeAllMarksWeakerMatches() async throws {
        let swap = try swap(await swappableLooks(), on: .shoes)
        let scope = swap.seeAllScope
        #expect(scope.garmentIDs == ["g-black-heels", "g-nude-flats", "g-white-sneakers"])
        #expect(scope.notes == ["g-white-sneakers": SwapText.mayNotMatch])
        #expect(scope.fixedKind == .shoes)
        #expect(swap.hasSeeAll)
    }

    /// LR-07.4: Find one only with Mine + one idea, and never from a suitcase.
    @Test func findOneOnlyWithMineAndOneIdea() async throws {
        #expect(try swap(await swappableLooks()).setup.allowsFindOne)
        #expect(try !swap(await swappableLooks(lookRequest(pieceMode: .onlyMine))).setup.allowsFindOne)
        let suitcase = await swappableLooks(lookRequest(source: .suitcase("s-weekend"), occasion: .casual))
        #expect(try !swap(suitcase).setup.allowsFindOne)
    }

    // MARK: Show 3 more

    /// Three at a time, then the end of the list.
    @Test func showThreeMorePagesThroughTheGoodMatches() throws {
        let garments = (0..<8).map { index in
            Garment(
                id: Garment.ID("t\(index)"), name: "Top \(index)", category: .top, colors: [.white],
                occasions: [.office], addedAt: ClosetTestTime.day(-10))
        }
        let base = [
            Garment(id: "top", name: "Top", category: .top, colors: [.white], addedAt: ClosetTestTime.now),
            Garment(id: "bottom", name: "Bottom", category: .bottom, colors: [.navy], addedAt: ClosetTestTime.now),
        ]
        let look = Look(
            id: "look",
            pieces: [
                LookPiece(id: "look-top", content: .garment("top")),
                LookPiece(id: "look-bottom", content: .garment("bottom")),
            ], occasion: .office, createdAt: ClosetTestTime.now)
        let swap = SwapModel(
            setup: SwapSetup(
                look: look, simple: nil,
                garments: Dictionary(uniqueKeysWithValues: (garments + base).map { ($0.id, $0) }), suitcases: [],
                situation: SwapSituation(
                    occasion: .office, date: ClosetTestTime.now, calendar: ClosetTestTime.calendar),
                sourceName: "Main closet", allowsFindOne: false))
        #expect(swap.options.ranked.count == 8)
        #expect(swap.visibleOptions.count == 3)
        #expect(swap.canShowMore)
        swap.showMore()
        #expect(swap.visibleOptions.count == 6)
        swap.showMore()
        #expect(swap.visibleOptions.count == 8)
        #expect(!swap.canShowMore)
        swap.showMore()
        #expect(swap.visibleOptions.count == 8)
        // Choosing another piece starts at three again.
        swap.choosePiece("look-bottom")
        #expect(swap.visibleOptions.count <= 3)
    }

    /// LR-07.5: with the large closet, ranking a piece's options and Show 3 more stay quick.
    @Test(.heavyMainActorWork) func theLargeClosetStaysQuick() async throws {
        let model = await swappableLooks(services: yourLooksServices(.large))
        let swap = try swap(model)
        #expect(model.garments.count > 2_000)
        let pieces = swap.pieces
        let ranking = SpeedCheck.fastest {
            for piece in pieces { swap.choosePiece(piece.id) }
        }
        #expect(ranking < SpeedCheck.limit(.milliseconds(250)), "Ranking every piece took \(ranking)")
        let paging = SpeedCheck.fastest {
            swap.choosePiece(pieces[0].id)
            swap.choosePiece(pieces[1].id)
            while swap.canShowMore { swap.showMore() }
        }
        #expect(paging < SpeedCheck.limit(.milliseconds(150)), "Show 3 more took \(paging)")
    }

    // MARK: Trying and using

    @Test func tryingAPieceShowsItInTheLook() async throws {
        let swap = try swap(await swappableLooks(), on: .shoes)
        #expect(swap.preview == nil)
        swap.select("g-black-heels")
        #expect(swap.preview == "g-black-heels")
        #expect(swap.shownLook.garmentIDs.contains("g-black-heels"))
        #expect(!swap.shownLook.garmentIDs.contains("g-tan-loafers"))
        #expect(swap.shownLook.id == swap.setup.look.id, "The bundle keeps its layout while trying")
        // Tapping it again, or Keep current, puts the look back.
        swap.select("g-black-heels")
        #expect(swap.preview == nil)
        swap.select("g-nude-flats")
        swap.keepCurrent()
        #expect(swap.shownLook == swap.setup.look)
        #expect(swap.swapped() == nil, "Nothing to use until she tries one")
    }

    /// FR-09: Use these shoes changes the shoes only, keeps the version, and marks them Swapped.
    @Test func usingASwapChangesOnePieceInYourLooks() async throws {
        let model = await swappableLooks()
        let original = try #require(model.currentLook)
        let swap = try swap(model, on: .shoes)
        swap.select("g-black-heels")
        let changed = try #require(swap.swapped())
        model.apply(changed)

        let current = try #require(model.currentLook)
        #expect(current.id == "edit-1")
        #expect(current.version == .simple)
        #expect(current.resultID == original.resultID)
        #expect(current.garmentIDs == ["g-navy-cardigan", "g-cream-sweater", "g-olive-trousers", "g-black-heels"])
        #expect(model.result?.simple == original, "The stylist's look is kept as it was")
        #expect(model.canUndoChange)
        let changes = YourLooksText.changes(
            in: current, simple: model.result?.simple, original: model.originalLook, garments: model.garments)
        let heels = try #require(current.pieces.first { $0.garmentID == "g-black-heels" })
        #expect(changes == [heels.id.rawValue: .swapped])
    }

    /// An idea piece can be swapped for one of hers.
    @Test func anIdeaCanBeSwappedForHerOwnPiece() async throws {
        let model = await swappableLooks()
        model.version = .somethingNew
        let swap = try swap(model, on: .bag)
        #expect(swap.piece?.isIdea == true)
        swap.select("g-burgundy-bag")
        let changed = try #require(swap.swapped())
        #expect(changed.ideas.isEmpty)
        #expect(changed.version == .somethingNew)
    }

    // MARK: Remove

    /// Remove this piece works while the rest is still a look, and says why when it isn't.
    @Test func removeThisPiece() async throws {
        let model = await swappableLooks()
        let top = try swap(model, on: .top)
        #expect(top.removalProblem == .needsMainPieces)
        #expect(top.removed() == nil)
        #expect(SwapText.whyNoRemove(.needsMainPieces).contains("a top and a bottom, or a dress"))

        let shoes = try swap(model, on: .shoes)
        #expect(shoes.removalProblem == nil)
        let removed = try #require(shoes.removed())
        model.apply(removed)
        #expect(model.currentLook?.garmentIDs == ["g-navy-cardigan", "g-cream-sweater", "g-olive-trousers"])
    }

    // MARK: Undo

    /// LR-08.2: Undo restores the exact earlier look, one change at a time.
    @Test func undoRestoresTheExactEarlierLook() async throws {
        let model = await swappableLooks()
        let original = try #require(model.currentLook)

        let shoes = try swap(model, on: .shoes)
        shoes.select("g-black-heels")
        model.apply(try #require(shoes.swapped()))
        let afterSwap = try #require(model.currentLook)

        let layer = try swap(model, on: .layer)
        model.apply(try #require(layer.removed()))
        #expect(model.currentLook?.garmentIDs.contains("g-navy-cardigan") == false)

        #expect(model.undoChange())
        #expect(model.currentLook == afterSwap)
        #expect(model.undoChange())
        #expect(model.currentLook == original)
        #expect(model.edits.isEmpty)
        #expect(!model.canUndoChange)
        #expect(!model.undoChange())
    }

    /// Changes belong to their version: switching shows each version as it is.
    @Test func eachVersionKeepsItsOwnChanges() async throws {
        let model = await swappableLooks()
        let shoes = try swap(model, on: .shoes)
        shoes.select("g-nude-flats")
        model.apply(try #require(shoes.swapped()))
        model.version = .dressedUp
        #expect(model.currentLook?.garmentIDs.contains("g-tan-loafers") == true)
        #expect(!model.canUndoChange)
        model.version = .simple
        #expect(model.currentLook?.garmentIDs.contains("g-nude-flats") == true)
    }

    /// Try a different outfit starts clean.
    @Test func aNewResultDropsTheChanges() async throws {
        let model = await swappableLooks()
        let shoes = try swap(model, on: .shoes)
        shoes.select("g-nude-flats")
        model.apply(try #require(shoes.swapped()))
        model.tryDifferentOutfit()
        await model.settle()
        #expect(model.edits.isEmpty)
        #expect(!model.canUndoChange)
    }

    // MARK: Saving

    /// Save look works on the changed look: it's saved as its own look, and the stylist's look
    /// stays unsaved background history.
    @Test func saveLookSavesTheChangedLook() async throws {
        let services = yourLooksServices()
        let model = await swappableLooks(services: services)
        let original = try #require(model.currentLook)
        let shoes = try swap(model, on: .shoes)
        shoes.select("g-black-heels")
        model.apply(try #require(shoes.swapped()))
        let changed = try #require(model.currentLook)

        let change = try await model.toggleSave(changed, name: "Cream & olive")
        #expect(change == .saved(changed.id))
        let stored = try await services.looks.look(changed.id)
        #expect(stored.isSaved)
        #expect(stored.name == "Cream & olive")
        #expect(stored.garmentIDs.contains("g-black-heels"))
        #expect(stored.version == .simple)
        #expect(try await services.looks.look(original.id).isSaved == false)
        #expect(model.savedLooks.contains { $0.id == changed.id })

        // Undoing the swap shows the stylist's look again, which isn't saved.
        model.undoChange()
        #expect(model.currentLook.map(model.isSaved) == false)
    }
}
