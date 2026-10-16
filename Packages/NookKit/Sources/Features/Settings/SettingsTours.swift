import Models

/// Help's quick tour (Phase 16b, `help-tour.html`): a topic, and Still stuck?.
enum HelpTour {
    enum Anchor {
        static let topic = TourAnchorID("help.topic")
        static let stillStuck = TourAnchorID("help.stillStuck")
    }

    static var definition: TourDefinition {
        .gotIt(
            .help,
            steps: [
                TourStep(
                    Anchor.topic,
                    title: String(
                        localized: "Find a simple answer", bundle: .module, comment: "Help tour, step 1 title"),
                    message: String(
                        localized: "Tap a question to open the answer. Tap it again to close it.", bundle: .module,
                        comment: "Help tour, step 1")),
                TourStep(
                    Anchor.stillStuck,
                    title: String(localized: "Still need a hand?", bundle: .module, comment: "Help tour, step 2 title"),
                    message: String(
                        localized:
                            "Still stuck? opens Send feedback, where you can write a private note about the app.",
                        bundle: .module, comment: "Help tour, step 2")),
            ])
    }
}

/// Send feedback's quick tour (Phase 16b, `feedback-tour.html`): her note, and Send privately.
enum FeedbackTour {
    enum Anchor {
        static let message = TourAnchorID("feedback.message")
        static let send = TourAnchorID("feedback.send")
    }

    static var definition: TourDefinition {
        .gotIt(
            .feedback,
            steps: [
                TourStep(
                    Anchor.message,
                    title: String(
                        localized: "Tell me what happened", bundle: .module, comment: "Send feedback tour, step 1 title"
                    ),
                    message: String(
                        localized: "Write what went wrong or what you would like changed.", bundle: .module,
                        comment: "Send feedback tour, step 1")),
                TourStep(
                    Anchor.send,
                    title: String(
                        localized: "Sending your note", bundle: .module, comment: "Send feedback tour, step 2 title"),
                    message: String(
                        localized:
                            "Send privately opens the share sheet. You choose where your note goes, like Messages or Mail.",
                        bundle: .module, comment: "Send feedback tour, step 2")),
            ])
    }
}

/// Privacy and terms' quick tour (Phase 16b, `privacy-tour.html`): what's sent later, and Delete
/// my data. The mockup's permission switches and Export a copy aren't built (docs/settings.md),
/// so the steps point at what stands in their place.
enum PrivacyTour {
    enum Anchor {
        static let later = TourAnchorID("privacy.later")
        static let deleteData = TourAnchorID("privacy.deleteData")
    }

    static var definition: TourDefinition {
        .gotIt(
            .privacy,
            steps: [
                TourStep(
                    Anchor.later,
                    title: String(
                        localized: "You choose what to share", bundle: .module, comment: "Privacy tour, step 1 title"),
                    message: String(
                        localized: "Nothing here is sent yet. Later, each of these asks you first.", bundle: .module,
                        comment: "Privacy tour, step 1")),
                TourStep(
                    Anchor.deleteData,
                    title: String(
                        localized: "Your information", bundle: .module, comment: "Privacy tour, step 2 title"),
                    message: String(
                        localized: "Delete my data erases everything the app keeps about you. It asks you first.",
                        bundle: .module, comment: "Privacy tour, step 2")),
            ])
    }
}
