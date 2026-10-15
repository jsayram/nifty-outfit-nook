import Models
import SwiftUI

extension EnvironmentValues {
    /// The app's services. The app target sets it once at the root; screens read it and never
    /// build services themselves. `nil` only in previews and tests that don't need data.
    @Entry public var services: NookServices?
}

/// Opens Saved Looks from another tab with screens pushed on it, as a frame on the Home shelf
/// does with a look, and Try it on's See the picture does with a picture (Phase 12b). The root
/// view sets it; elsewhere it does nothing.
struct OpenInSavedLooksAction: Sendable {
    let open: @MainActor @Sendable ([SavedLooksDestination]) -> Void

    @MainActor func callAsFunction(_ path: [SavedLooksDestination]) {
        open(path)
    }
}

extension EnvironmentValues {
    @Entry var openInSavedLooks = OpenInSavedLooksAction { _ in }
}

/// Opens Closet from another tab with screens pushed on it (Phase 13): Home's suitcase opens
/// Suitcases and its hamper opens Laundry there, since both live in Closet (RD-13), and the
/// mockups' Suitcases and Laundry go back to Closet. The root view sets it; elsewhere it does
/// nothing.
struct OpenInClosetAction: Sendable {
    let open: @MainActor @Sendable ([ClosetDestination]) -> Void

    @MainActor func callAsFunction(_ path: [ClosetDestination]) {
        open(path)
    }
}

extension EnvironmentValues {
    @Entry var openInCloset = OpenInClosetAction { _ in }
}
