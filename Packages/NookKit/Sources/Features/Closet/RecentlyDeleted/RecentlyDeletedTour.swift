import Models

/// Recently deleted's quick tour (Stage A audit; the mockups have none): how long a piece waits
/// here, and Restore. Both steps point at the first piece.
enum RecentlyDeletedTour {
    enum Anchor {
        static let piece = TourAnchorID("recentlyDeleted.piece")
        static let restore = TourAnchorID("recentlyDeleted.restore")
    }

    static var definition: TourDefinition {
        .gotIt(
            .recentlyDeleted,
            steps: [
                TourStep(
                    Anchor.piece,
                    title: String(
                        localized: "Kept for 30 days", bundle: .module, comment: "Recently deleted tour, step 1 title"),
                    message: String(
                        localized: "Pieces you delete wait here. Each one shows the day it goes for good.",
                        bundle: .module, comment: "Recently deleted tour, step 1")),
                TourStep(
                    Anchor.restore,
                    title: String(
                        localized: "Changed your mind?", bundle: .module, comment: "Recently deleted tour, step 2 title"
                    ),
                    message: String(
                        localized: "Tap Restore to put a piece back in your closet.", bundle: .module,
                        comment: "Recently deleted tour, step 2")),
            ])
    }
}
