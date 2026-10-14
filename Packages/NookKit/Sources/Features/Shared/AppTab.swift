import Foundation

/// The app's tabs, in tab bar order. Home comes first (PRD amendment RD-01).
nonisolated public enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case closet
    case savedLooks

    public var id: Self { self }

    /// The tab's label, as shown in the tab bar.
    public var title: String {
        switch self {
        case .home: String(localized: "Home", bundle: .module, comment: "Tab bar label")
        case .closet: String(localized: "Closet", bundle: .module, comment: "Tab bar label")
        case .savedLooks: String(localized: "Saved Looks", bundle: .module, comment: "Tab bar label")
        }
    }

    /// The SF Symbol for the tab, matching the mockup icons (house, hanger, bookmark).
    public var systemImage: String {
        switch self {
        case .home: "house"
        case .closet: "hanger"
        case .savedLooks: "bookmark"
        }
    }
}
