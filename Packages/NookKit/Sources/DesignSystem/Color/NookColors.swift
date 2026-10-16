import SwiftUI

extension Color {
    /// A colour token from `Colors.xcassets`. It follows light and dark appearance by itself.
    nonisolated public init(token: ColorToken) {
        self.init(token.assetName, bundle: .module)
    }

    /// The app's colour tokens, for example `Color.nook.background`.
    nonisolated public static let nook = NookColors()
}

extension ShapeStyle where Self == Color {
    /// The app's colour tokens where a style is expected, for example `.foregroundStyle(.nook.textPrimary)`.
    nonisolated public static var nook: NookColors { Color.nook }
}

/// Named access to every `ColorToken` as a SwiftUI `Color`.
nonisolated public struct NookColors: Sendable {
    // Interface
    public var background: Color { Color(token: .background) }
    public var backgroundLow: Color { Color(token: .backgroundLow) }
    public var surface: Color { Color(token: .surface) }
    public var tint: Color { Color(token: .tint) }
    public var tintStrong: Color { Color(token: .tintStrong) }
    public var textPrimary: Color { Color(token: .textPrimary) }
    public var textSecondary: Color { Color(token: .textSecondary) }
    public var accent: Color { Color(token: .accent) }
    public var accentPressed: Color { Color(token: .accentPressed) }
    public var onAccent: Color { Color(token: .onAccent) }
    public var accentSoft: Color { Color(token: .accentSoft) }
    public var chevron: Color { Color(token: .chevron) }
    public var track: Color { Color(token: .track) }
    public var divider: Color { Color(token: .divider) }
    public var shadow: Color { Color(token: .shadow) }
    public var shadowLarge: Color { Color(token: .shadowLarge) }
    public var tourScrim: Color { Color(token: .tourScrim) }
    public var tourGlow: Color { Color(token: .tourGlow) }
    public var tourRim: Color { Color(token: .tourRim) }
    public var tourCard: Color { Color(token: .tourCard) }

    // Status
    public var success: Color { Color(token: .success) }
    public var successSurface: Color { Color(token: .successSurface) }
    public var warning: Color { Color(token: .warning) }
    public var warningSurface: Color { Color(token: .warningSurface) }
    public var error: Color { Color(token: .error) }
    public var errorSurface: Color { Color(token: .errorSurface) }

    // Room and art
    public var floor: Color { Color(token: .floor) }
    public var floorLow: Color { Color(token: .floorLow) }
    public var floorLine: Color { Color(token: .floorLine) }
    public var skyTop: Color { Color(token: .skyTop) }
    public var skyBottom: Color { Color(token: .skyBottom) }
    public var artSage: Color { Color(token: .artSage) }
    public var artSageDeep: Color { Color(token: .artSageDeep) }
    public var artSageLine: Color { Color(token: .artSageLine) }
    public var artSand: Color { Color(token: .artSand) }
    public var artStone: Color { Color(token: .artStone) }
    public var artButter: Color { Color(token: .artButter) }
    public var artButterLine: Color { Color(token: .artButterLine) }
    public var signPanel: Color { Color(token: .signPanel) }
    public var signText: Color { Color(token: .signText) }
    public var stickerEdge: Color { Color(token: .stickerEdge) }

    /// The wall, from `background` at the top to `backgroundLow` at the bottom (`.screen` in the mockups).
    public var wallGradient: LinearGradient {
        LinearGradient(colors: [background, backgroundLow], startPoint: .top, endPoint: .bottom)
    }

    /// The welcome screen's sky, from `skyTop` to `skyBottom` (Phase 17).
    public var skyGradient: LinearGradient {
        LinearGradient(colors: [skyTop, skyBottom], startPoint: .top, endPoint: .bottom)
    }

    /// The floor, from `floor` to `floorLow`.
    public var floorGradient: LinearGradient {
        LinearGradient(colors: [floor, floorLow], startPoint: .top, endPoint: .bottom)
    }

    /// A 1 pt divider line that fades out at both ends and never reaches the edges (`--soft-divider`).
    /// Decorative only.
    public var softDivider: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: divider.opacity(0), location: 0),
                .init(color: divider, location: 0.22),
                .init(color: divider, location: 0.78),
                .init(color: divider.opacity(0), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
