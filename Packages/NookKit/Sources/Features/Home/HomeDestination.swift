import Models

/// A screen Home opens by pushing it. Closet and Saved Looks are tabs, so the wardrobe and the
/// shelf switch tabs instead (see `RoomControl.route(for:)`).
nonisolated enum HomeDestination: Hashable, Sendable {
    /// The Style Me request (RD-02). `choosingOccasion` comes from the calendar, so Phase 10a
    /// can open the Occasion sheet straight away.
    case styleMe(choosingOccasion: Bool)
    case suitcases
    /// Laundry, when tracking is on (RD-11).
    case laundry
    case help
    case feedback
    case privacy
    case profile

    /// The screen's title.
    var title: String {
        switch self {
        case .styleMe: String(localized: "Style Me", bundle: .module, comment: "Screen title")
        case .suitcases: String(localized: "Suitcases", bundle: .module, comment: "Screen title")
        case .laundry: String(localized: "Laundry", bundle: .module, comment: "Screen title")
        case .help: String(localized: "Help", bundle: .module, comment: "Screen title")
        case .feedback: String(localized: "Send feedback", bundle: .module, comment: "Screen title")
        case .privacy: String(localized: "Privacy and terms", bundle: .module, comment: "Screen title")
        case .profile: String(localized: "Profile", bundle: .module, comment: "Screen title")
        }
    }

    /// The SF Symbol on the screen's placeholder, matching the mockup icons.
    var systemImage: String {
        switch self {
        case .styleMe: "sparkles"
        case .suitcases: "suitcase.rolling"
        case .laundry: "basket"
        case .help: "questionmark.circle"
        case .feedback: "bubble.left"
        case .privacy: "hand.raised"
        case .profile: "person.crop.circle"
        }
    }

    /// A stable name for UI tests.
    var identifier: String {
        switch self {
        case .styleMe: "styleMe"
        case .suitcases: "suitcases"
        case .laundry: "laundry"
        case .help: "help"
        case .feedback: "feedback"
        case .privacy: "privacy"
        case .profile: "profile"
        }
    }
}

/// A short sheet Home opens over the room.
nonisolated enum HomeSheet: String, Identifiable, Hashable, Sendable {
    /// What laundry tracking does, with Turn on, when it's off (RD-11).
    case laundryTracking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .laundryTracking:
            String(localized: "Laundry tracking is off", bundle: .module, comment: "Sheet title")
        }
    }

    var subtitle: String? {
        switch self {
        case .laundryTracking:
            String(
                localized: "It’s optional, and off for now.", bundle: .module,
                comment: "Under the laundry tracking sheet's title")
        }
    }
}

/// Where tapping something in the room goes.
nonisolated enum HomeRoute: Hashable, Sendable {
    case tab(AppTab)
    case push(HomeDestination)
    case sheet(HomeSheet)
}
