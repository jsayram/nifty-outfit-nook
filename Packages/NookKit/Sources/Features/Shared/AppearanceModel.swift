import Models
import SwiftUI

/// Light or dark for the whole app (N3). The lamp in her room and the Dark mode switch in
/// Profile both change this one choice, so they always agree. The root view applies it to the
/// window with `preferredColorScheme`, which sheets follow too.
@MainActor
@Observable
final class AppearanceModel {
    private(set) var choice: AppearanceChoice

    @ObservationIgnored private let store: any AppearanceStore

    init(store: any AppearanceStore) {
        self.store = store
        choice = store.current()
    }

    /// What the root asks the window for: `nil` follows the iPhone.
    var colorScheme: ColorScheme? {
        switch choice {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The Dark mode switch, and the lamp: her choice from now on, kept across launches.
    func setDark(_ isDark: Bool) {
        choice = isDark ? .dark : .light
        store.save(choice)
    }

    /// The lamp: turns the lights off when the app shows light, and on when it shows dark.
    /// `showing` is what's on screen now, which may be the iPhone's appearance.
    func toggleLights(showing: ColorScheme) {
        setDark(showing == .light)
    }

    /// Reads the store again, after Delete my data erased it.
    func reload() {
        choice = store.current()
    }
}

/// Turns dark mode on or off for the whole app (N3). The root view sets it; elsewhere, in
/// previews and snapshot tests, it does nothing.
struct SetDarkModeAction: Sendable {
    let set: @MainActor @Sendable (Bool) -> Void

    @MainActor func callAsFunction(_ isDark: Bool) {
        set(isDark)
    }
}

extension EnvironmentValues {
    @Entry var setDarkMode = SetDarkModeAction { _ in }
}
