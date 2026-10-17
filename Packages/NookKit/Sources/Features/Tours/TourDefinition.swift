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
    /// True for a tour on a sheet (Try it on, Stage A audit). The sheet draws it over itself,
    /// since anything the root draws stays under a sheet (`TourOverlay`, `RootTabView`).
    var isInSheet = false
}

extension TourStep {
    init(_ anchor: TourAnchorID, title: String, message: String) {
        self.init(anchor: anchor, title: title, message: message)
    }
}

extension TourDefinition {
    /// A screen's tour that ends with Got it, as every tour but Home's does (Phase 16b). Every
    /// tour starts at version 1; a version goes up only when the screen's controls or the steps
    /// really change, never for a copy fix (PRD §7.8).
    static func gotIt(_ id: TourID, version: Int = 1, isInSheet: Bool = false, steps: [TourStep]) -> TourDefinition {
        TourDefinition(
            id: id, version: version, steps: steps, finishTitle: TourText.gotIt, finishFocus: nil, isInSheet: isInSheet)
    }
}
