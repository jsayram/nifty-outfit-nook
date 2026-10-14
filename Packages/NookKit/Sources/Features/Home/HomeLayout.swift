import SwiftUI

/// Which of Home's three layouts the screen shows (RD-01, RD-01.5).
///
/// - `room`: the illustrated bedroom (`home.html`), on a phone held upright and on iPad.
/// - `largeText`: at the accessibility text sizes, a banner of the room and large rows for
///   every control (`home-ax.html`). It wins in any orientation, since it scrolls.
/// - `sideways`: on a phone held sideways, a closer view of the room with the controls as
///   tiles beside it (`home-landscape.html`).
///
/// Switching layout keeps everything on the screen (the model, a pushed screen, an open sheet),
/// since only the view inside `HomeScreen` changes.
nonisolated enum HomeLayout: String, CaseIterable, Hashable, Sendable {
    case room
    case largeText
    case sideways

    init(dynamicTypeSize: DynamicTypeSize, verticalSizeClass: UserInterfaceSizeClass?) {
        if dynamicTypeSize.isAccessibilitySize {
            self = .largeText
        } else if verticalSizeClass == .compact {
            self = .sideways
        } else {
            self = .room
        }
    }
}

extension RoomControl {
    /// What VoiceOver and Voice Control use for a control drawn as a row or tile, where the words
    /// are on screen: the same words, so she can say what she sees. The room's objects keep
    /// `accessibilityLabel(for:)`, which names the object.
    func rowLabel(for content: HomeRoomContent) -> String {
        switch self {
        case .wardrobe, .nameSign:
            return accessibilityLabel(for: content)
        case .savedLooks:
            return String(localized: "Saved Looks", bundle: .module, comment: "VoiceOver label: opens Saved Looks")
        case .occasion:
            return String(localized: "Occasion", bundle: .module, comment: "Row on Home: opens Style Me's occasion")
        case .laptop:
            return String(localized: "Style Me", bundle: .module, comment: "Button on Home: opens Style Me")
        case .helpDrawer:
            return String(localized: "Help", bundle: .module, comment: "Row on Home: opens Help")
        case .feedbackDrawer:
            return String(localized: "Send feedback", bundle: .module, comment: "Row on Home: opens Send feedback")
        case .privacyDrawer:
            return String(
                localized: "Privacy and terms", bundle: .module, comment: "Row on Home: opens Privacy and terms")
        case .suitcase:
            let source = content.source
            let parts = [source.name, source.countText, source.scopeText].compactMap(\.self)
            return String(
                localized: "Source: \(parts.joined(separator: ", "))", bundle: .module,
                comment: "VoiceOver label for the Source row. The values are the source name, piece count and scope.")
        case .hamper:
            guard let hamper = content.hamper else {
                return String(localized: "Laundry", bundle: .module, comment: "VoiceOver label for the Laundry row")
            }
            return String(
                localized: "Laundry: \(hamper.plateText)", bundle: .module,
                comment: "VoiceOver label for the Laundry row, with its state such as Off or 2 to wash")
        }
    }
}
