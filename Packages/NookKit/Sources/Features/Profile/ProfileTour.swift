import Models

/// Profile's quick tour (Phase 16b, `settings-tour.html`): the name on the sign, Fit and
/// measurements, and App tours.
enum ProfileTour {
    enum Anchor {
        static let name = TourAnchorID("profile.name")
        static let fit = TourAnchorID("profile.fit")
        static let appTours = TourAnchorID("profile.appTours")
    }

    static var definition: TourDefinition {
        .gotIt(
            .profile,
            steps: [
                TourStep(
                    Anchor.name,
                    title: String(
                        localized: "Your name on the sign", bundle: .module, comment: "Profile tour, step 1 title"),
                    message: String(
                        localized: "Tap here to change the name shown in your room.", bundle: .module,
                        comment: "Profile tour, step 1")),
                TourStep(
                    Anchor.fit,
                    title: String(
                        localized: "Help with your fit", bundle: .module, comment: "Profile tour, step 2 title"),
                    message: String(
                        localized: "Add sizes or measurements if you want. You can leave them blank.", bundle: .module,
                        comment: "Profile tour, step 2")),
                TourStep(
                    Anchor.appTours,
                    title: String(
                        localized: "A little reminder", bundle: .module, comment: "Profile tour, step 3 title"),
                    message: String(
                        localized: "App tours lets you replay any of these little guides whenever you like.",
                        bundle: .module, comment: "Profile tour, step 3")),
            ])
    }
}

/// Fit and measurements' quick tour (Phase 16b, `fit-tour.html`): usual fit, the units, weight,
/// and Add a piece that fits you well. LR-18 and LR-13 ask the tour to use the screen's own
/// words: "Saved until you change it" and "Add a piece that fits you well".
enum FitTour {
    enum Anchor {
        static let usualFit = TourAnchorID("fit.usualFit")
        static let units = TourAnchorID("fit.units")
        static let weight = TourAnchorID("fit.weight")
        static let addPiece = TourAnchorID("fit.addPiece")
    }

    static var definition: TourDefinition {
        .gotIt(
            .fit,
            steps: [
                TourStep(
                    Anchor.usualFit,
                    title: String(
                        localized: "How do you like your clothes?", bundle: .module, comment: "Fit tour, step 1 title"),
                    message: String(
                        localized: "Choose the fit that feels best to you. It’s saved until you change it.",
                        bundle: .module, comment: "Fit tour, step 1 (LR-18)")),
                TourStep(
                    Anchor.units,
                    title: String(
                        localized: "Use the units you know", bundle: .module, comment: "Fit tour, step 2 title"),
                    message: String(
                        localized: "Choose the measurements you are comfortable with.", bundle: .module,
                        comment: "Fit tour, step 2")),
                TourStep(
                    Anchor.weight,
                    title: String(
                        localized: "Your weight is optional", bundle: .module, comment: "Fit tour, step 3 title"),
                    message: String(
                        localized: "Tap Weight to add it, or leave it blank if you prefer.", bundle: .module,
                        comment: "Fit tour, step 3")),
                TourStep(
                    Anchor.addPiece,
                    title: String(
                        localized: "Add a piece that fits you well", bundle: .module, comment: "Fit tour, step 4 title"),
                    message: String(
                        localized:
                            "Pick something you own that fits just right. We’ll use its brand and size to suggest sizes for you.",
                        bundle: .module, comment: "Fit tour, step 4 (LR-13)")),
            ])
    }
}
