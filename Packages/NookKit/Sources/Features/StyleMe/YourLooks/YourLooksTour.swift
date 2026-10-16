import Models

/// Your looks' quick tour (Phase 16b, `results-tour.html`), once the looks are ready: the three
/// versions, Save look, Try it on and Swap a piece.
///
/// The mockup's first step was Shuffle, which Lily's sign-off replaced with one outfit in three
/// versions (LR-05a), so it points at the version switch instead. When a result has only one
/// version there's no switch, and the tour has the other three steps.
enum YourLooksTour {
    enum Anchor {
        static let versions = TourAnchorID("results.versions")
        static let save = TourAnchorID("results.save")
        static let tryOn = TourAnchorID("results.tryOn")
        static let swap = TourAnchorID("results.swap")
    }

    static func definition(hasVersions: Bool) -> TourDefinition {
        let versions = TourStep(
            Anchor.versions,
            title: String(localized: "Three versions", bundle: .module, comment: "Your looks tour, step 1 title"),
            message: String(
                localized:
                    "Simple, Dressed up and Something new are the same outfit, styled three ways. Tap one to see it.",
                bundle: .module, comment: "Your looks tour, step 1: the version switch (LR-05a)"))
        let rest = [
            TourStep(
                Anchor.save,
                title: String(
                    localized: "Keep a favourite", bundle: .module, comment: "Your looks tour, Save look title"),
                message: String(
                    localized: "Tap Save look to find this outfit in Saved Looks later.", bundle: .module,
                    comment: "Your looks tour, Save look")),
            TourStep(
                Anchor.tryOn,
                title: String(
                    localized: "Picture the outfit", bundle: .module, comment: "Your looks tour, Try it on title"),
                message: String(
                    localized:
                        "Try it on makes a simulated picture of this outfit. It shows the style, not the exact fit.",
                    bundle: .module, comment: "Your looks tour, Try it on")),
            TourStep(
                Anchor.swap,
                title: String(
                    localized: "Change just one piece", bundle: .module, comment: "Your looks tour, Swap a piece title"),
                message: String(
                    localized: "Like the outfit but fancy another top? Swap a piece keeps the rest of the look.",
                    bundle: .module, comment: "Your looks tour, Swap a piece")),
        ]
        return .gotIt(.yourLooks, steps: hasVersions ? [versions] + rest : rest)
    }
}
