import Models

/// Suitcases' quick tour (Phase 16b, `suitcases-tour.html`): "+ Add a suitcase" and the list of
/// suitcases to choose from.
enum SuitcasesTour {
    enum Anchor {
        static let add = TourAnchorID("suitcases.add")
        static let sources = TourAnchorID("suitcases.sources")
    }

    static var definition: TourDefinition {
        .gotIt(
            .suitcases,
            steps: [
                TourStep(
                    Anchor.add,
                    title: String(
                        localized: "Pack a little collection", bundle: .module, comment: "Suitcases tour, step 1 title"),
                    message: String(
                        localized: "Make a suitcase for a trip, a place or a few favourite pieces.", bundle: .module,
                        comment: "Suitcases tour, step 1")),
                TourStep(
                    Anchor.sources,
                    title: String(
                        localized: "Pick your suitcase", bundle: .module, comment: "Suitcases tour, step 2 title"),
                    // A row chooses the suitcase and its arrow opens it, so the mockup's words
                    // say both.
                    message: String(
                        localized: "Tap a suitcase to choose it for Style Me, or its arrow to see what’s packed.",
                        bundle: .module, comment: "Suitcases tour, step 2")),
            ])
    }
}

/// One suitcase's quick tour (Phase 16b, `suitcase-tour.html`): Name and picture, packing, and
/// Style me from this suitcase once something is packed.
enum SuitcaseTour {
    enum Anchor {
        static let edit = TourAnchorID("suitcase.edit")
        static let pack = TourAnchorID("suitcase.pack")
        static let styleMe = TourAnchorID("suitcase.styleMe")
    }

    static func definition(hasPieces: Bool) -> TourDefinition {
        let steps = [
            TourStep(
                Anchor.edit,
                title: String(
                    localized: "Make the name yours", bundle: .module, comment: "Suitcase tour, step 1 title"),
                message: String(
                    localized: "Give your suitcase a name that is easy to remember.", bundle: .module,
                    comment: "Suitcase tour, step 1")),
            TourStep(
                Anchor.pack,
                title: String(
                    localized: "Choose what goes in", bundle: .module, comment: "Suitcase tour, step 2 title"),
                message: String(
                    localized: "Add or remove clothes here. Removing one keeps it in your closet.", bundle: .module,
                    comment: "Suitcase tour, step 2")),
            TourStep(
                Anchor.styleMe,
                title: String(
                    localized: "Style from this suitcase", bundle: .module, comment: "Suitcase tour, step 3 title"),
                message: String(
                    localized: "Use the packed clothes for outfit ideas. You can switch back to your whole closet too.",
                    bundle: .module, comment: "Suitcase tour, step 3")),
        ]
        // An empty suitcase has nothing to style from yet.
        return .gotIt(.suitcase, steps: hasPieces ? steps : Array(steps.prefix(2)))
    }
}
