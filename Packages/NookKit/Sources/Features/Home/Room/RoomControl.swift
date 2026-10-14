import CoreGraphics
import Models

/// The things in the room that do something (RD-01). Each one is a single button for VoiceOver,
/// with a label that names the object and where it goes.
///
/// The cases are in VoiceOver reading order: the title first, then the big pieces from the top
/// of the room down, then the floor.
nonisolated enum RoomControl: String, CaseIterable, Hashable, Sendable {
    case wardrobe
    case savedLooks
    case nameSign
    case occasion
    case laptop
    case helpDrawer
    case feedbackDrawer
    case privacyDrawer
    case suitcase
    case hamper

    /// The tap area in stage units, before it's grown to 44 x 44 points.
    var stageRect: CGRect {
        switch self {
        case .wardrobe: RoomStage.wardrobe
        case .savedLooks: RoomStage.savedLooks
        case .nameSign: RoomStage.sign
        case .occasion: RoomStage.occasion
        case .laptop: RoomStage.laptopScreen
        case .helpDrawer: RoomStage.drawers[0]
        case .feedbackDrawer: RoomStage.drawers[1]
        case .privacyDrawer: RoomStage.drawers[2]
        case .suitcase: RoomStage.suitcase
        case .hamper: RoomStage.hamper
        }
    }

    /// Where it goes. The hamper depends on whether laundry tracking is on (RD-11.3).
    func route(hamper: HamperState?) -> HomeRoute {
        switch self {
        case .wardrobe: .tab(.closet)
        case .savedLooks: .tab(.savedLooks)
        case .nameSign: .push(.profile)
        case .occasion: .push(.styleMe(choosingOccasion: true))
        case .laptop: .push(.styleMe(choosingOccasion: false))
        case .helpDrawer: .push(.help)
        case .feedbackDrawer: .push(.feedback)
        case .privacyDrawer: .push(.privacy)
        case .suitcase: .push(.suitcases)
        case .hamper:
            switch hamper {
            case .allClean, .toWash: .push(.laundry)
            case .off, nil: .push(.laundryTracking)
            }
        }
    }

    /// Higher reads first. Keeps VoiceOver in `allCases` order whatever the drawing order is.
    var sortPriority: Double {
        Double(Self.allCases.count - (Self.allCases.firstIndex(of: self) ?? 0))
    }

    /// A stable name for UI tests.
    var identifier: String { "home.\(rawValue)" }

    /// What VoiceOver says first: the object and where it goes, with the live values on it.
    func accessibilityLabel(for content: HomeRoomContent) -> String {
        switch self {
        case .wardrobe:
            return String(localized: "Wardrobe: Closet", bundle: .module, comment: "VoiceOver label for the wardrobe")
        case .savedLooks:
            return String(localized: "Shelf: Saved Looks", bundle: .module, comment: "VoiceOver label for the shelf")
        case .nameSign:
            guard let stored = content.signName, !SignName.isFallback(stored) else {
                return String(
                    localized: "Name sign, no name yet", bundle: .module,
                    comment: "VoiceOver label for the name sign when no name is set")
            }
            return String(
                localized: "Name sign: \(stored)", bundle: .module, comment: "VoiceOver label for the name sign")
        case .occasion:
            return String(localized: "Calendar: Occasion", bundle: .module, comment: "VoiceOver label for the calendar")
        case .laptop:
            return String(localized: "Laptop: Style Me", bundle: .module, comment: "VoiceOver label for the laptop")
        case .helpDrawer:
            return String(localized: "Top drawer: Help", bundle: .module, comment: "VoiceOver label for a desk drawer")
        case .feedbackDrawer:
            return String(
                localized: "Middle drawer: Send feedback", bundle: .module, comment: "VoiceOver label for a desk drawer"
            )
        case .privacyDrawer:
            return String(
                localized: "Bottom drawer: Privacy and terms", bundle: .module,
                comment: "VoiceOver label for a desk drawer")
        case .suitcase:
            let source = content.source
            let parts = [source.name, source.countText, source.scopeText].compactMap(\.self)
            return String(
                localized: "Suitcase: Source, \(parts.joined(separator: ", "))", bundle: .module,
                comment: "VoiceOver label for the suitcase. The values are the source name, piece count and scope.")
        case .hamper:
            guard let hamper = content.hamper else {
                return String(localized: "Hamper: Laundry", bundle: .module, comment: "VoiceOver label for the hamper")
            }
            return String(
                localized: "Hamper: Laundry, \(hamper.plateText)", bundle: .module,
                comment: "VoiceOver label for the hamper, with its state such as Off or 2 to wash")
        }
    }

    /// What VoiceOver says after a pause: what tapping does.
    func accessibilityHint(for content: HomeRoomContent) -> String {
        switch self {
        case .wardrobe: String(localized: "Opens your closet.", bundle: .module, comment: "VoiceOver hint")
        case .savedLooks: String(localized: "Opens your saved looks.", bundle: .module, comment: "VoiceOver hint")
        case .nameSign: String(localized: "Opens Profile.", bundle: .module, comment: "VoiceOver hint")
        case .occasion:
            String(localized: "Opens Style Me to pick the occasion.", bundle: .module, comment: "VoiceOver hint")
        case .laptop:
            String(
                localized: "Opens Style Me. Nothing is sent until you ask.", bundle: .module, comment: "VoiceOver hint")
        case .helpDrawer: String(localized: "Opens Help.", bundle: .module, comment: "VoiceOver hint")
        case .feedbackDrawer: String(localized: "Opens Send feedback.", bundle: .module, comment: "VoiceOver hint")
        case .privacyDrawer: String(localized: "Opens Privacy and terms.", bundle: .module, comment: "VoiceOver hint")
        case .suitcase:
            String(localized: "Opens Suitcases, where you pick the source.", bundle: .module, comment: "VoiceOver hint")
        case .hamper:
            switch content.hamper {
            case .allClean, .toWash:
                String(localized: "Opens Laundry.", bundle: .module, comment: "VoiceOver hint")
            case .off, nil:
                String(localized: "Explains laundry tracking.", bundle: .module, comment: "VoiceOver hint")
            }
        }
    }
}
