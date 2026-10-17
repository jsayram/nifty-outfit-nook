import Models

/// The Try it on sheet's quick tour (Stage A audit; the mockups have none): what the picture is,
/// and Make a picture. It's on a sheet, so the sheet draws it (`TourOverlay`).
enum TryOnTour {
    enum Anchor {
        static let about = TourAnchorID("tryOn.about")
        static let make = TourAnchorID("tryOn.make")
    }

    static var definition: TourDefinition {
        .gotIt(
            .tryOn, isInSheet: true,
            steps: [
                TourStep(
                    Anchor.about,
                    title: String(
                        localized: "A simulated picture", bundle: .module, comment: "Try it on tour, step 1 title"),
                    // The last line is Your looks' tour's (RD-06, LR-12).
                    message: String(
                        localized:
                            "Your pieces on a plain background, with no person in it. It shows the style, not the exact fit.",
                        bundle: .module, comment: "Try it on tour, step 1")),
                TourStep(
                    Anchor.make,
                    title: String(
                        localized: "Only when you ask", bundle: .module, comment: "Try it on tour, step 2 title"),
                    message: String(
                        localized: "Tap Make a picture when you’re ready. Nothing is made until you do.",
                        bundle: .module, comment: "Try it on tour, step 2")),
            ])
    }
}
