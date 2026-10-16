import Models

/// Laundry's quick tours (Phase 16b): one while tracking is on (`laundry-tour.html`) and one
/// while it's off (`laundry-off-tour.html`). They're separate tours, as in the mockups, since the
/// screen's controls are different.
enum LaundryTour {
    enum Anchor {
        static let scope = TourAnchorID("laundry.scope")
        static let markClean = TourAnchorID("laundry.markClean")
        static let cleanAll = TourAnchorID("laundry.cleanAll")
        static let turnOn = TourAnchorID("laundry.turnOn")
        static let leaveOff = TourAnchorID("laundry.leaveOff")
    }

    /// Tracking on, with pieces in the wash. The scope chips only show while Style Me's source
    /// is a suitcase, so without them the tour has two steps.
    static func definition(hasScope: Bool) -> TourDefinition {
        let scope = TourStep(
            Anchor.scope,
            title: String(localized: "Which clothes?", bundle: .module, comment: "Laundry tour, step 1 title"),
            message: String(
                localized: "Choose your whole closet or the suitcase you are using.", bundle: .module,
                comment: "Laundry tour, step 1"))
        let rest = [
            TourStep(
                Anchor.markClean,
                title: String(
                    localized: "Fresh from the wash?", bundle: .module, comment: "Laundry tour, Mark clean title"),
                message: String(
                    localized: "Tap Mark clean when a piece is ready to wear again.", bundle: .module,
                    comment: "Laundry tour, Mark clean")),
            TourStep(
                Anchor.cleanAll,
                title: String(
                    localized: "All finished?", bundle: .module, comment: "Laundry tour, Mark all clean title"),
                message: String(
                    localized: "Mark all clean lets you finish the whole list together. You will be asked to confirm.",
                    bundle: .module, comment: "Laundry tour, Mark all clean")),
        ]
        return .gotIt(.laundry, steps: hasScope ? [scope] + rest : rest)
    }

    /// Tracking off.
    static var offDefinition: TourDefinition {
        .gotIt(
            .laundryOff,
            steps: [
                TourStep(
                    Anchor.turnOn,
                    title: String(
                        localized: "Keep track of the wash", bundle: .module,
                        comment: "Laundry is off tour, step 1 title"),
                    message: String(
                        localized: "Turn this on if you want Style Me to skip clothes that are in the wash.",
                        bundle: .module, comment: "Laundry is off tour, step 1")),
                TourStep(
                    Anchor.leaveOff,
                    title: String(
                        localized: "You can leave it off", bundle: .module, comment: "Laundry is off tour, step 2 title"
                    ),
                    // The mockup's Not now isn't on this screen; its link to Profile is.
                    message: String(
                        localized:
                            "Leave it off if you would rather keep things simple. You can turn it on later in Profile.",
                        bundle: .module, comment: "Laundry is off tour, step 2")),
            ])
    }
}
