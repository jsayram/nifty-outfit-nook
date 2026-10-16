import Models

/// Make your own look's quick tour (Phase 16b, `editor-tour.html`): Add a piece, the name and
/// Save look. LR-08 asks it to start with "Build an outfit yourself, piece by piece."
enum LookBuilderTour {
    enum Anchor {
        static let add = TourAnchorID("builder.add")
        static let name = TourAnchorID("builder.name")
        static let save = TourAnchorID("builder.save")
    }

    static var definition: TourDefinition {
        .gotIt(
            .lookBuilder,
            steps: [
                TourStep(
                    Anchor.add,
                    title: String(
                        localized: "Choose your pieces", bundle: .module,
                        comment: "Make your own look tour, step 1 title"
                    ),
                    message: String(
                        localized:
                            "Build an outfit yourself, piece by piece. Tap Add a piece to pick from your closet.",
                        bundle: .module, comment: "Make your own look tour, step 1 (LR-08)")),
                TourStep(
                    Anchor.name,
                    title: String(
                        localized: "Give it a name", bundle: .module, comment: "Make your own look tour, step 2 title"),
                    message: String(
                        localized: "A name makes your outfit easier to find later.", bundle: .module,
                        comment: "Make your own look tour, step 2")),
                TourStep(
                    Anchor.save,
                    title: String(
                        localized: "Keep this outfit", bundle: .module, comment: "Make your own look tour, step 3 title"
                    ),
                    message: String(
                        localized: "Tap Save look when it feels right. You can change a piece later with Swap a piece.",
                        bundle: .module, comment: "Make your own look tour, step 3 (LR-08)")),
            ])
    }
}
