import Foundation
import Models
import Testing

/// Sticker or tile (Phase 8b): one rule for every screen, from the piece's photo and cutout.
struct GarmentArtChoiceTests {
    private let photo = PhotoReference.stored("p-1")
    private let cutoutImage = PhotoReference.stored("p-1-cutout")

    private func cutout(
        instances: Int = 1, coverage: Double = 0.3, largest: Double = 1, edges: CutoutEdges = [], soft: Double = 0.05
    ) -> GarmentCutout {
        GarmentCutout(
            image: cutoutImage,
            quality: CutoutQuality(
                instanceCount: instances, coverage: coverage, largestInstanceShare: largest, touchedEdges: edges,
                softEdgeRatio: soft, subjectBounds: CutoutBounds(x: 0.2, y: 0.2, width: 0.6, height: 0.6)))
    }

    @Test func noPhotoIsTheDrawing() {
        #expect(GarmentArtChoice(photo: .noPhoto, cutout: nil) == .drawing)
        // A cutout without a photo can't happen, but if it did the drawing still wins.
        #expect(GarmentArtChoice(photo: .noPhoto, cutout: cutout()) == .drawing)
        #expect(GarmentArtChoice.drawing.isCutOut)
    }

    @Test func aPhotoWithoutACutoutYetIsATile() {
        let choice = GarmentArtChoice(photo: photo, cutout: nil)
        #expect(choice == .photoTile(photo, concerns: []))
        #expect(!choice.isCutOut)
    }

    @Test func aCleanCutoutIsUsed() {
        let choice = GarmentArtChoice(photo: photo, cutout: cutout())
        #expect(choice == .cutout(cutoutImage))
        #expect(choice.isCutOut)
    }

    /// Each concern on its own sends the piece to its tile, and says why.
    @Test(arguments: [CutoutThresholds.Concern.tooSmall, .tooLarge, .severalSubjects, .runsOffThePhoto, .unsureEdges])
    func aMessyCutoutFallsBackToTheTile(concern: CutoutThresholds.Concern) {
        let messy: GarmentCutout
        switch concern {
        case .tooSmall: messy = cutout(coverage: 0.02)
        case .tooLarge: messy = cutout(coverage: 0.95)
        case .severalSubjects: messy = cutout(instances: 2, largest: 0.6)
        case .runsOffThePhoto: messy = cutout(edges: [.bottom, .left])
        case .unsureEdges: messy = cutout(soft: 0.4)
        }
        #expect(GarmentArtChoice(photo: photo, cutout: messy) == .photoTile(photo, concerns: [concern]))
    }

    @Test func thresholdsCanBeChanged() {
        var strict = CutoutThresholds.current
        strict.maximumSoftEdgeRatio = 0.01
        #expect(
            GarmentArtChoice(photo: photo, cutout: cutout(), thresholds: strict)
                == .photoTile(
                    photo, concerns: [.unsureEdges]))
    }

    @Test func aGarmentChoosesFromItsOwnPhotoAndCutout() {
        var garment = Garment(id: "g-1", name: "Tee", category: .top, photo: photo, addedAt: .now)
        #expect(GarmentArtChoice(garment) == .photoTile(photo, concerns: []))
        garment.cutout = cutout()
        #expect(GarmentArtChoice(garment) == .cutout(cutoutImage))
    }

    @Test func theAppUsesThePhase8aProposalUntilTheBenchmark() {
        #expect(CutoutThresholds.current == .proposed)
    }

    // MARK: The cutout on a garment

    @Test func aNewPhotoDropsTheOldCutout() {
        var garment = Garment(id: "g-1", name: "Tee", category: .top, photo: photo, cutout: cutout(), addedAt: .now)
        var details = GarmentDetails(garment)
        details.name = "Navy tee"
        details.apply(to: &garment)
        #expect(garment.cutout == cutout())
        details.photo = .stored("p-2")
        details.apply(to: &garment)
        #expect(garment.cutout == nil)
        #expect(garment.photo == .stored("p-2"))
    }

    @Test func theCutoutSurvivesEncoding() throws {
        let garment = Garment(id: "g-1", name: "Tee", category: .top, photo: photo, cutout: cutout(), addedAt: .now)
        let decoded = try JSONDecoder().decode(Garment.self, from: JSONEncoder().encode(garment))
        #expect(decoded == garment)
    }

    /// A garment saved before Phase 8b has no cutout key, and still reads.
    @Test func aGarmentWithoutACutoutKeyStillDecodes() throws {
        let garment = Garment(id: "g-1", name: "Tee", category: .top, addedAt: Date(timeIntervalSince1970: 0))
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(garment)) as? [String: Any])
        object["cutout"] = nil
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(Garment.self, from: data) == garment)
    }
}
