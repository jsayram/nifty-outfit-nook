import Models

/// Add a piece's quick tour (Phase 16b, `garment-edit-tour.html`), on its first step: the photo
/// choices and Describe in words.
enum AddPieceTour {
    enum Anchor {
        static let photo = TourAnchorID("addPiece.photo")
        static let words = TourAnchorID("addPiece.words")
    }

    static var definition: TourDefinition {
        .gotIt(
            .addPiece,
            steps: [
                TourStep(
                    Anchor.photo,
                    title: String(localized: "Add a photo", bundle: .module, comment: "Add a piece tour, step 1 title"),
                    // The mockup's "These buttons use an example photo in this preview" now says
                    // what this build does.
                    message: String(
                        localized:
                            "Choose a photo, or take one, to add your piece. For now each one adds a sample picture.",
                        bundle: .module, comment: "Add a piece tour, step 1")),
                TourStep(
                    Anchor.words,
                    title: String(
                        localized: "Words work too", bundle: .module, comment: "Add a piece tour, step 2 title"),
                    message: String(
                        localized: "No photo yet? Describe your piece instead. You can add a photo later.",
                        bundle: .module, comment: "Add a piece tour, step 2")),
            ])
    }
}
