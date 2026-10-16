import Foundation
import Models
import Testing

/// How try-on pictures and their looks link (Phase 12b, RD-08.2).
struct TryOnLinksTests {
    private let look = Make.look("o-1", garments: ["g-top", "g-bottom", "g-shoes"])

    private func picture(_ id: TryOnPicture.ID, of look: Look, day: Int) -> TryOnPicture {
        TryOnPicture(id: id, of: look, image: .simulated, createdAt: TestTime.day(day))
    }

    private func saved(_ look: Look) -> Look {
        var look = look
        look.isSaved = true
        look.name = "Office navy"
        return look
    }

    @Test func aPictureKeepsTheLookAsItWas() {
        let look = saved(look)
        let picture = picture("p-1", of: look, day: -1)
        #expect(picture.lookID == "o-1")
        #expect(picture.captured.pieces == look.pieces)
        #expect(picture.captured.name == "Office navy")
        #expect(picture.image == .simulated)
    }

    @Test func aSavedLookWithTheSamePiecesIsCurrent() {
        let look = saved(look)
        let picture = picture("p-1", of: look, day: -1)
        #expect(TryOnLinks.status(of: picture, looks: [look.id: look]) == .current(look))
    }

    /// A swap after the picture: the look is still there, the picture shows an earlier version.
    @Test func aChangedLookIsAnEarlierVersion() {
        let before = saved(look)
        let picture = picture("p-1", of: before, day: -1)
        var after = before
        after.pieces[0] = LookPiece(id: "o-1-g-other", content: .garment("g-other-top"))
        #expect(TryOnLinks.status(of: picture, looks: [after.id: after]) == .changed(after))
    }

    /// Deleted from the store, or unsaved back into history: the picture stays, unlinked.
    @Test func aDeletedOrUnsavedLookIsNotSaved() {
        let look = saved(look)
        let picture = picture("p-1", of: look, day: -1)
        #expect(TryOnLinks.status(of: picture, looks: [:]) == .notSaved)
        var unsaved = look
        unsaved.isSaved = false
        #expect(TryOnLinks.status(of: picture, looks: [unsaved.id: unsaved]) == .notSaved)
    }

    @Test func aLooksPicturesAreItsOwnNewestFirst() {
        let look = saved(look)
        let other = saved(Make.look("o-2", garments: ["g-dress", "g-shoes"]))
        let pictures = [
            picture("p-old", of: look, day: -9),
            picture("p-other", of: other, day: -1),
            picture("p-new", of: look, day: -2),
            picture("p-same-day-b", of: look, day: -5),
            picture("p-same-day-a", of: look, day: -5),
        ]
        #expect(
            TryOnLinks.pictures(of: look.id, in: pictures).map(\.id) == [
                "p-new", "p-same-day-a", "p-same-day-b", "p-old",
            ])
        #expect(TryOnLinks.pictures(of: "o-none", in: pictures).isEmpty)
    }

    /// FR-59: Try it on offers the newest picture of exactly these pieces.
    @Test func aPictureOfTheSamePiecesCanBeReused() {
        let look = saved(look)
        var changed = look
        changed.pieces.removeLast()
        let pictures = [
            picture("p-of-changed", of: changed, day: -1),
            picture("p-older", of: look, day: -5),
            picture("p-newer", of: look, day: -3),
        ]
        #expect(TryOnLinks.reusable(for: look, in: pictures)?.id == "p-newer")
        #expect(TryOnLinks.reusable(for: changed, in: pictures)?.id == "p-of-changed")
        #expect(TryOnLinks.reusable(for: Make.look("o-2", garments: ["g-top"]), in: pictures) == nil)
    }

    /// Order, piece IDs and "Same as Simple" don't change what a picture shows; the garments and
    /// ideas do.
    @Test func samePiecesComparesWhatIsWorn() {
        let pieces = look.pieces
        let shuffled = [pieces[2], pieces[0], pieces[1]].map {
            LookPiece(id: LookPiece.ID("x-\($0.id.rawValue)"), content: $0.content, isSameAsSimple: !$0.isSameAsSimple)
        }
        #expect(TryOnLinks.samePieces(pieces, shuffled))
        #expect(!TryOnLinks.samePieces(pieces, Array(pieces.dropLast())))
        let idea = PieceIdea(name: "Cropped cardigan", category: .layer, colors: [.cream])
        let withIdea = pieces + [LookPiece(id: "o-1-idea", content: .idea(idea))]
        let withOtherIdea =
            pieces + [LookPiece(id: "o-1-idea", content: .idea(PieceIdea(name: "Vest", category: .layer)))]
        #expect(!TryOnLinks.samePieces(withIdea, withOtherIdea))
        // Two of the same garment against one of each.
        let doubled = [pieces[0], pieces[0], pieces[1]]
        #expect(!TryOnLinks.samePieces(doubled, Array(pieces)))
    }
}
