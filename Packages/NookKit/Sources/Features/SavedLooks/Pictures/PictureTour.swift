import Models

/// A try-on picture's quick tour (Phase 16b, `picture-tour.html`): See the look and Delete
/// picture. The mockup's favourite star isn't in the app, so its step points at Delete picture,
/// which has Undo.
enum PictureTour {
    enum Anchor {
        static let seeLook = TourAnchorID("picture.seeLook")
        static let delete = TourAnchorID("picture.delete")
    }

    static var definition: TourDefinition {
        .gotIt(
            .picture,
            steps: [
                TourStep(
                    Anchor.seeLook,
                    title: String(
                        localized: "Back to the outfit", bundle: .module, comment: "Try-on picture tour, step 1 title"),
                    message: String(
                        localized: "Tap See the look to open the outfit behind the picture.", bundle: .module,
                        comment: "Try-on picture tour, step 1")),
                TourStep(
                    Anchor.delete,
                    title: String(localized: "Tidy up", bundle: .module, comment: "Try-on picture tour, step 2 title"),
                    message: String(
                        localized: "Tap Delete picture to remove one you don’t want. You can undo it.", bundle: .module,
                        comment: "Try-on picture tour, step 2")),
            ])
    }
}
