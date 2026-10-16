import Models

/// Saved Looks' quick tour (Phase 16b, `saved-tour.html`, `ipad-saved-tour.html`): her looks,
/// the Pictures tab and search. The first step points at her first look, which is what "Tap an
/// outfit to open it" is about; the second at the Looks and Pictures switch.
enum SavedLooksTour {
    enum Anchor {
        static let firstLook = TourAnchorID("savedLooks.firstLook")
        static let tabs = TourAnchorID("savedLooks.tabs")
        static let search = TourAnchorID("savedLooks.search")
    }

    static var definition: TourDefinition {
        .gotIt(
            .savedLooks,
            steps: [
                TourStep(
                    Anchor.firstLook,
                    title: String(
                        localized: "Your favourite outfits", bundle: .module, comment: "Saved Looks tour, step 1 title"
                    ),
                    message: String(
                        localized: "Looks keeps the outfits you saved. Tap an outfit to open it.", bundle: .module,
                        comment: "Saved Looks tour, step 1")),
                TourStep(
                    Anchor.tabs,
                    title: String(
                        localized: "Your outfit pictures", bundle: .module, comment: "Saved Looks tour, step 2 title"),
                    message: String(
                        localized: "Pictures keeps your saved try-on pictures.", bundle: .module,
                        comment: "Saved Looks tour, step 2")),
                TourStep(
                    Anchor.search,
                    title: String(
                        localized: "Find something quickly", bundle: .module, comment: "Saved Looks tour, step 3 title"
                    ),
                    message: String(
                        localized: "Type a word, like navy, to find a saved outfit or picture.", bundle: .module,
                        comment: "Saved Looks tour, step 3")),
            ])
    }
}
