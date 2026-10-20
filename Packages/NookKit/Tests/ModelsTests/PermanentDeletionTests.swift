import Foundation
import Models
import NookTestSupport
import Testing

/// "Delete permanently now" (PRD §7.4, Phase 21a): what the preview lists.
struct PermanentDeletionTests {
    private let piece = Garment(
        id: "g1", name: "Navy dress pants", category: .bottom, photo: .sample("navy"), deletedAt: TestTime.now,
        addedAt: TestTime.day(-30))

    private func look(_ id: Look.ID, saved: Bool, pieces: [Garment.ID], daysAgo: Int = 0) -> Look {
        Look(
            id: id, pieces: pieces.map { LookPiece(id: LookPiece.ID("\(id)-\($0)"), content: .garment($0)) },
            name: saved ? "Look \(id)" : nil, isSaved: saved, createdAt: TestTime.day(-daysAgo))
    }

    @Test func listsSavedLooksSuitcasesTheEditAndPictures() {
        let older = look("l-older", saved: true, pieces: ["g1", "g2"], daysAgo: 5)
        let newer = look("l-newer", saved: true, pieces: ["g1"], daysAgo: 1)
        let unsaved = look("l-unsaved", saved: false, pieces: ["g1"])
        let other = look("l-other", saved: true, pieces: ["g2"])
        let suitcases = [
            Suitcase(id: "s2", name: "Weekend", garmentIDs: ["g1"], createdAt: TestTime.now),
            Suitcase(id: "s1", name: "Beach", garmentIDs: ["g1", "g2"], createdAt: TestTime.now),
            Suitcase(id: "s3", name: "Work", garmentIDs: ["g2"], createdAt: TestTime.now),
        ]
        let drafts = [
            GarmentDraft(
                target: .garment("g1"), step: .details, details: GarmentDetails(name: "x"), base: GarmentDetails(),
                savedAt: TestTime.now)
        ]
        let pictures = [
            TryOnPicture(id: "p1", of: newer, image: .simulated, createdAt: TestTime.now),
            TryOnPicture(id: "p2", of: other, image: .simulated, createdAt: TestTime.now),
        ]
        let preview = PermanentDeletion.preview(
            of: piece, looks: [older, unsaved, other, newer], suitcases: suitcases, drafts: drafts, pictures: pictures)
        #expect(preview.savedLooks.map(\.id) == ["l-newer", "l-older"])
        #expect(preview.suitcases.map(\.name) == ["Beach", "Weekend"])
        #expect(preview.hasUnsavedEdit)
        #expect(preview.pictureCount == 1)
        #expect(preview.hasPhoto)
    }

    @Test func aPieceNothingUsesHasABarePreview() {
        let preview = PermanentDeletion.preview(of: piece, looks: [], suitcases: [], drafts: [], pictures: [])
        #expect(preview == PermanentDeletionPreview(piece: piece))
        // An unsaved new piece isn't this piece's edit.
        let add = GarmentDraft(
            target: .newPiece, step: .details, details: GarmentDetails(name: "x"), base: GarmentDetails(),
            savedAt: TestTime.now)
        #expect(
            !PermanentDeletion.preview(of: piece, looks: [], suitcases: [], drafts: [add], pictures: []).hasUnsavedEdit)
    }
}
