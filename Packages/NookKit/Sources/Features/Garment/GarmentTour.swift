import Models

/// Garment detail's quick tour (Phase 16b, `garment-tour.html`): Edit, Style with this and Add
/// to a suitcase.
enum GarmentTour {
    enum Anchor {
        static let edit = TourAnchorID("garment.edit")
        static let styleWithThis = TourAnchorID("garment.styleWithThis")
        static let addToSuitcase = TourAnchorID("garment.addToSuitcase")
    }

    static var definition: TourDefinition {
        .gotIt(
            .garment,
            steps: [
                TourStep(
                    Anchor.edit,
                    title: String(
                        localized: "Change the details", bundle: .module, comment: "Garment tour, step 1 title"),
                    message: String(
                        localized: "Tap Edit to change the name, photo or details of this piece.", bundle: .module,
                        comment: "Garment tour, step 1")),
                TourStep(
                    Anchor.styleWithThis,
                    title: String(
                        localized: "Build a look around it", bundle: .module, comment: "Garment tour, step 2 title"),
                    message: String(
                        localized: "Start here when you want an outfit with this piece.", bundle: .module,
                        comment: "Garment tour, step 2")),
                TourStep(
                    Anchor.addToSuitcase,
                    title: String(localized: "Pack it away", bundle: .module, comment: "Garment tour, step 3 title"),
                    message: String(
                        localized: "Add this piece to a suitcase. It still stays in your closet.", bundle: .module,
                        comment: "Garment tour, step 3")),
            ])
    }
}
