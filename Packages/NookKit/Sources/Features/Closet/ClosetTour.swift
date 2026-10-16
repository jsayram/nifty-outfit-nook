import Models

/// Closet's quick tour (Phase 16b, `closet-tour.html`, `ipad-closet-tour.html`): Add a piece,
/// search and the filters. Where a piece shows beside the grid (iPad), the last step points at
/// that column instead, in the iPad mockup's words.
enum ClosetTour {
    enum Anchor {
        static let addPiece = TourAnchorID("closet.addPiece")
        static let search = TourAnchorID("closet.search")
        static let filters = TourAnchorID("closet.filters")
        static let beside = TourAnchorID("closet.beside")
    }

    static func definition(detailBeside: Bool) -> TourDefinition {
        .gotIt(
            .closet,
            steps: [
                TourStep(
                    Anchor.addPiece,
                    title: String(localized: "Add your clothes", bundle: .module, comment: "Closet tour, step 1 title"),
                    message: String(
                        localized: "Tap Add a piece to add a photo or describe something you own.", bundle: .module,
                        comment: "Closet tour, step 1")),
                TourStep(
                    Anchor.search,
                    title: String(localized: "Find a piece", bundle: .module, comment: "Closet tour, step 2 title"),
                    message: String(
                        localized: "Type a word, like blue or jeans, to find your clothes.", bundle: .module,
                        comment: "Closet tour, step 2")),
                detailBeside
                    ? TourStep(
                        Anchor.beside,
                        title: String(
                            localized: "A closer look", bundle: .module,
                            comment: "Closet tour on iPad, step 3 title: the piece beside the grid"),
                        message: String(
                            localized: "The piece you choose appears on the right. Tap Edit to change its details.",
                            bundle: .module, comment: "Closet tour on iPad, step 3"))
                    : TourStep(
                        Anchor.filters,
                        title: String(
                            localized: "Narrow it down", bundle: .module, comment: "Closet tour, step 3 title"),
                        message: String(
                            localized: "Use these little buttons to show just the clothes you want to see.",
                            bundle: .module, comment: "Closet tour, step 3")),
            ])
    }
}
