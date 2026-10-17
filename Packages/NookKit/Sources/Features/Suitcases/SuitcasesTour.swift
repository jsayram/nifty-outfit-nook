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

/// All suitcases' quick tour (Stage A audit; the mockups have none), from See all: search, the
/// Archived filter when she has archived suitcases, and the main closet.
enum AllSuitcasesTour {
    enum Anchor {
        static let search = TourAnchorID("allSuitcases.search")
        static let archived = TourAnchorID("allSuitcases.archived")
        static let mainCloset = TourAnchorID("allSuitcases.mainCloset")
    }

    static func definition(hasArchived: Bool) -> TourDefinition {
        let search = TourStep(
            Anchor.search,
            title: String(localized: "Find a suitcase", bundle: .module, comment: "All suitcases tour, step 1 title"),
            message: String(
                localized: "Type a name to find one quickly.", bundle: .module, comment: "All suitcases tour, step 1"))
        let archived = TourStep(
            Anchor.archived,
            title: String(
                localized: "Put away, not gone", bundle: .module, comment: "All suitcases tour, archived step title"),
            message: String(
                localized: "Archived suitcases are kept here, out of the way. Tap to show them.", bundle: .module,
                comment: "All suitcases tour, archived step"))
        let mainCloset = TourStep(
            Anchor.mainCloset,
            title: String(
                localized: "Back to everything", bundle: .module, comment: "All suitcases tour, last step title"),
            message: String(
                localized: "Tap Main closet to style from all your clothes again.", bundle: .module,
                comment: "All suitcases tour, last step"))
        // Without archived suitcases there's no filter to show.
        return .gotIt(.allSuitcases, steps: hasArchived ? [search, archived, mainCloset] : [search, mainCloset])
    }
}
