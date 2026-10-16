import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// The three frames under the Home shelf show her most recently saved looks (Phase 12a).
@MainActor
struct HomeFramedLooksTests {
    @Test func demoFramesShowTheThreeNewestSavedLooks() async {
        let model = HomeModel()
        await model.load(
            from: FixtureServices.make(set: .demo, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar))
        let framed = model.content.framedLooks
        #expect(framed.map(\.id) == ["o-brunch-idea", "o-weekend", "o-interview"])
        #expect(
            framed.map(\.name) == ["Brunch with a new layer", "Weekend olive and brick", "Interview navy and pink"])
        // A top over a bottom: the pink shirt over the olive trousers.
        #expect(framed[0].pieces.map(\.category) == [.top, .bottom])
        #expect(framed[0].pieces.map(\.colors) == [[.pink], [.olive]])
    }

    @Test func noSavedLooksLeaveTheFramesEmpty() async {
        let model = HomeModel()
        await model.load(
            from: FixtureServices.make(set: .empty, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar))
        #expect(model.content.framedLooks.isEmpty)
    }

    /// One saved look fills one frame; the others stay empty.
    @Test func fewerLooksThanFrames() {
        let look = Look(
            id: "o-one", pieces: [LookPiece(id: "p-1", content: .garment("g-dress"))], name: "Blue dress",
            isSaved: true, createdAt: ClosetTestTime.now)
        let dress = Garment(
            id: "g-dress", name: "Dress", category: .dress, colors: [.blue], addedAt: ClosetTestTime.now)
        let framed = HomeModel.framedLooks(from: [look], garments: [dress])
        #expect(framed.count == 1)
        #expect(framed[0].pieces.map(\.category) == [.dress])
    }

    /// A dress alone; a top (or a layer) over a bottom; otherwise the first two.
    @Test func mainPieces() {
        func piece(_ category: GarmentCategory) -> FramedLook.Piece {
            FramedLook.Piece(category: category, colors: [], photo: .noPhoto)
        }
        let kinds = { (pieces: [FramedLook.Piece]) in FramedLook.mainPieces(of: pieces).map(\.category) }
        #expect(kinds([piece(.layer), piece(.dress), piece(.shoes)]) == [.dress])
        #expect(kinds([piece(.layer), piece(.top), piece(.bottom), piece(.shoes)]) == [.top, .bottom])
        #expect(kinds([piece(.layer), piece(.bottom), piece(.shoes)]) == [.layer, .bottom])
        #expect(kinds([piece(.top), piece(.shoes), piece(.bag)]) == [.top, .shoes])
        #expect(kinds([]).isEmpty)
    }
}
