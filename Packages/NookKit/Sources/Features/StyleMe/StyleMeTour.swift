import Models

/// Style Me's quick tour (Phase 16b, `styleme-tour.html`): the source, the occasion and Style me.
/// It starts on her first visit (PRD §7.8); Your looks has its own.
enum StyleMeTour {
    enum Anchor {
        static let source = TourAnchorID("styleMe.source")
        static let occasion = TourAnchorID("styleMe.occasion")
        static let go = TourAnchorID("styleMe.go")
    }

    static var definition: TourDefinition {
        .gotIt(
            .styleMe,
            steps: [
                TourStep(
                    Anchor.source,
                    title: String(localized: "Which clothes?", bundle: .module, comment: "Style Me tour, step 1 title"),
                    message: String(
                        localized: "Pick your whole closet or one suitcase. I’ll use the clothes you choose.",
                        bundle: .module, comment: "Style Me tour, step 1")),
                TourStep(
                    Anchor.occasion,
                    title: String(
                        localized: "What are your plans?", bundle: .module, comment: "Style Me tour, step 2 title"),
                    message: String(
                        localized: "Tap here to choose what you are dressing for, like work or a dinner out.",
                        bundle: .module, comment: "Style Me tour, step 2")),
                TourStep(
                    Anchor.go,
                    title: String(
                        localized: "Ready for outfit ideas?", bundle: .module, comment: "Style Me tour, step 3 title"),
                    message: String(
                        localized: "Tap Style me when you are ready. Your outfit ideas come next.", bundle: .module,
                        comment: "Style Me tour, step 3")),
            ])
    }
}
