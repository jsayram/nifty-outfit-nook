import Models

/// A saved look's quick tour (Phase 16b, `look-tour.html`): Wear today, Swap a piece and Rename.
///
/// The mockup's Edit and favourite star aren't in the app: LR-08 made Swap a piece the way to
/// change a saved look, and favourites have no Stage A screen. Their steps point at Swap a piece
/// and Rename instead.
enum LookTour {
    enum Anchor {
        static let wearToday = TourAnchorID("lookDetail.wearToday")
        static let swap = TourAnchorID("lookDetail.swap")
        static let rename = TourAnchorID("lookDetail.rename")
    }

    static var definition: TourDefinition {
        .gotIt(
            .look,
            steps: [
                TourStep(
                    Anchor.wearToday,
                    title: String(
                        localized: "Wear this one", bundle: .module, comment: "Saved look tour, step 1 title"),
                    message: String(
                        localized: "Tap Wear today to mark this outfit as worn today.", bundle: .module,
                        comment: "Saved look tour, step 1")),
                TourStep(
                    Anchor.swap,
                    title: String(
                        localized: "Make it yours", bundle: .module, comment: "Saved look tour, step 2 title"),
                    message: String(
                        localized: "Tap Swap a piece to change one piece. The rest of the outfit stays.",
                        bundle: .module, comment: "Saved look tour, step 2 (LR-08)")),
                TourStep(
                    Anchor.rename,
                    title: String(
                        localized: "Give it a name", bundle: .module, comment: "Saved look tour, step 3 title"),
                    message: String(
                        localized: "Tap Rename to change what this outfit is called.", bundle: .module,
                        comment: "Saved look tour, step 3")),
            ])
    }
}
