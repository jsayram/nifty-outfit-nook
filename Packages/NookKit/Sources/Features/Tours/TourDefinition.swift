import Models

/// A named spot on a screen that a tour step points at, such as Home's laptop. The screen marks
/// the view with `.tourAnchor(_:label:action:)`; every layout of the screen marks its own view
/// with the same anchor, so the tour follows whichever layout is showing.
struct TourAnchorID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// One step of a tour: the control it points at and what the card says about it.
struct TourStep: Hashable, Sendable {
    var anchor: TourAnchorID
    var title: String
    var message: String
}

/// A screen's tour: its stable ID, its content version and its steps, in the words for the
/// layout that's showing (PRD §7.8).
struct TourDefinition: Hashable, Sendable {
    var id: TourID
    /// Goes up only when the tour's controls or workflow change, so it shows once more.
    var version: Int
    var steps: [TourStep]
    /// The last step's button, which names what to do next.
    var finishTitle: String
    /// Where VoiceOver goes when the last step's button closes the tour. Skip and the other ways
    /// out send it to the control of the step that was showing.
    var finishFocus: TourAnchorID?
}
