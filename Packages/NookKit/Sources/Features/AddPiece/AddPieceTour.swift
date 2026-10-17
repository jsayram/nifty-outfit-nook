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

/// The quick tour for editing a piece she already has (Stage A audit; the mockups have none):
/// the photo, the details, and Save.
enum EditPieceTour {
    enum Anchor {
        static let photo = TourAnchorID("editPiece.photo")
        static let name = TourAnchorID("editPiece.name")
        static let save = TourAnchorID("editPiece.save")
    }

    static var definition: TourDefinition {
        .gotIt(
            .editPiece,
            steps: [
                TourStep(
                    Anchor.photo,
                    title: String(
                        localized: "The picture", bundle: .module, comment: "Edit a piece tour, step 1 title"),
                    message: String(
                        localized: "Add or change the photo here. For now it adds a sample picture.",
                        bundle: .module, comment: "Edit a piece tour, step 1")),
                TourStep(
                    Anchor.name,
                    title: String(
                        localized: "Fix any detail", bundle: .module, comment: "Edit a piece tour, step 2 title"),
                    message: String(
                        localized: "Change the name, kind, colours or anything else. The rest stays as it was.",
                        bundle: .module, comment: "Edit a piece tour, step 2")),
                TourStep(
                    Anchor.save,
                    title: String(
                        localized: "Keep your changes", bundle: .module, comment: "Edit a piece tour, step 3 title"),
                    message: String(
                        localized: "Tap Save when you’re done. Cancel leaves the piece as it was.", bundle: .module,
                        comment: "Edit a piece tour, step 3")),
            ])
    }
}
