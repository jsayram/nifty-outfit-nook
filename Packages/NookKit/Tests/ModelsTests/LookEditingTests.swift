import Foundation
import Models
import NookTestSupport
import Testing

struct LookEditingTests {
    private let simple = Make.look("simple", version: .simple, garments: ["top", "bottom", "shoes"])
    private var dressedUp: Look {
        var look = Make.look(
            "dressed", version: .dressedUp, garments: ["top2", "bottom", "shoes"], sameAsSimple: ["bottom", "shoes"])
        look.resultID = "r-1"
        look.name = "Saved name"
        look.isSaved = true
        look.wornOn = [TestTime.day(-2)]
        look.occasion = .office
        look.source = .suitcase("s-1")
        return look
    }

    /// FR-09: one piece changes, in its place; everything else stays.
    @Test func replacingChangesOnePieceAndKeepsTheRest() throws {
        let original = dressedUp
        let swapped = try #require(
            LookEditing.replacing(
                "dressed-shoes", with: "shoes2", in: original, simple: simple, newID: "edit-1", at: TestTime.now))
        #expect(swapped.id == "edit-1")
        #expect(swapped.garmentIDs == ["top2", "bottom", "shoes2"])
        #expect(swapped.pieces[0] == original.pieces[0])
        #expect(swapped.pieces[1] == original.pieces[1])
        #expect(swapped.pieces[2].id == "edit-1-shoes2")
        // Version context stays; saving, wear and the name start again.
        #expect(swapped.resultID == "r-1")
        #expect(swapped.version == .dressedUp)
        #expect(swapped.occasion == .office)
        #expect(swapped.source == .suitcase("s-1"))
        #expect(!swapped.isSaved && swapped.name == nil && swapped.wornOn.isEmpty)
        #expect(swapped.createdAt == TestTime.now)
        // The new piece isn't in Simple; the shared ones still are.
        #expect(swapped.pieces.map(\.isSameAsSimple) == [false, true, false])
    }

    @Test func replacingNeedsAPieceAndANewGarment() {
        #expect(
            LookEditing.replacing("nope", with: "x", in: simple, simple: simple, newID: "e", at: TestTime.now) == nil)
        #expect(
            LookEditing.replacing(
                "simple-top", with: "bottom", in: simple, simple: simple, newID: "e", at: TestTime.now)
                == nil)
    }

    @Test func anIdeaCanBeSwappedForAPieceSheOwns() throws {
        let idea = PieceIdea(name: "Cropped cardigan", category: .layer, colors: [.cream])
        let somethingNew = Make.look("new", version: .somethingNew, garments: ["top", "bottom", "shoes"], idea: idea)
        let swapped = try #require(
            LookEditing.replacing(
                "new-idea", with: "cardigan", in: somethingNew, simple: simple, newID: "e", at: TestTime.now))
        #expect(swapped.ideas.isEmpty)
        #expect(swapped.garmentIDs == ["top", "bottom", "shoes", "cardigan"])
    }

    @Test func removingTakesOnePieceOut() throws {
        let removed = try #require(
            LookEditing.removing("simple-shoes", from: simple, simple: simple, newID: "e", at: TestTime.now))
        #expect(removed.garmentIDs == ["top", "bottom"])
        #expect(removed.pieces.allSatisfy { $0.isSameAsSimple })
        #expect(LookEditing.removing("nope", from: simple, simple: simple, newID: "e", at: TestTime.now) == nil)
    }

    @Test func aLookSheMadeHasNoSameAsSimpleMarks() throws {
        let made = Make.look("made", version: nil, garments: ["top", "bottom"])
        let swapped = try #require(
            LookEditing.replacing("made-top", with: "top2", in: made, simple: nil, newID: "e", at: TestTime.now))
        #expect(swapped.pieces.allSatisfy { !$0.isSameAsSimple })
        #expect(swapped.version == nil)
    }

    @Test func categoriesWithoutAPiece() {
        let garments: [Garment.ID: Garment] = [
            "top": Make.garment("top", .top), "bottom": Make.garment("bottom", .bottom),
            "shoes": Make.garment("shoes", .shoes),
        ]
        #expect(LookEditing.categories(of: simple, without: "simple-top", garments: garments) == [.bottom, .shoes])
        #expect(LookEditing.categories(of: simple, without: nil, garments: garments) == [.top, .bottom, .shoes])
    }
}
