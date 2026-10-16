import Foundation

/// Words every quick tour shares (Phase 16b).
nonisolated enum TourText {
    /// The last button of every tour but Home's, which says "Start styling" (PRD §7.8).
    static var gotIt: String {
        String(localized: "Got it", bundle: .module, comment: "Last button of a quick tour; closes it")
    }

    /// What VoiceOver hears on a control in a tour's spotlight, before anything else.
    static var endsTour: String {
        String(
            localized: "Ends the tour.", bundle: .module,
            comment: "VoiceOver hint on a control in a quick tour's spotlight, before what the control does")
    }

    /// "Ends the tour." and what the control does.
    static func hint(_ action: String) -> String {
        "\(endsTour) \(action)"
    }
}
