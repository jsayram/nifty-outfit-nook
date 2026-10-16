import Models

/// Swap a piece's quick tour (Phase 16b, `swap-tour.html`): which piece, the options, Use this,
/// and Remove this piece, which LR-08 added after the mockup.
enum SwapTour {
    enum Anchor {
        static let pieces = TourAnchorID("swap.pieces")
        static let options = TourAnchorID("swap.options")
        static let use = TourAnchorID("swap.use")
        static let remove = TourAnchorID("swap.remove")
    }

    static var definition: TourDefinition {
        .gotIt(
            .swap,
            steps: [
                TourStep(
                    Anchor.pieces,
                    title: String(localized: "Which piece?", bundle: .module, comment: "Swap tour, step 1 title"),
                    message: String(
                        localized: "Pick the part of the outfit you want to change.", bundle: .module,
                        comment: "Swap tour, step 1")),
                TourStep(
                    Anchor.options,
                    title: String(localized: "Pick a replacement", bundle: .module, comment: "Swap tour, step 2 title"),
                    message: String(
                        localized: "Tap a piece you like from these choices.", bundle: .module,
                        comment: "Swap tour, step 2")),
                TourStep(
                    Anchor.use,
                    title: String(localized: "Keep your change", bundle: .module, comment: "Swap tour, step 3 title"),
                    message: String(
                        localized: "Tap Use this to put the new piece into your outfit.", bundle: .module,
                        comment: "Swap tour, step 3")),
                TourStep(
                    Anchor.remove,
                    title: String(localized: "Don’t need it?", bundle: .module, comment: "Swap tour, step 4 title"),
                    message: String(
                        localized: "Remove this piece takes it out of the outfit. You can undo it.", bundle: .module,
                        comment: "Swap tour, step 4: Remove this piece (LR-08)")),
            ])
    }
}
