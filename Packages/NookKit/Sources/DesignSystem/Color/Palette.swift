/// One colour token's two appearances.
nonisolated public struct TokenValue: Hashable, Sendable {
    public let light: RGBA
    public let dark: RGBA

    public init(light: RGBA, dark: RGBA) {
        self.light = light
        self.dark = dark
    }

    public subscript(appearance: Appearance) -> RGBA {
        switch appearance {
        case .light: light
        case .dark: dark
        }
    }
}

/// Light or dark appearance.
nonisolated public enum Appearance: String, CaseIterable, Sendable {
    case light
    case dark
}

/// The single source of truth for colour values.
///
/// Light values are Lily's warm neutral palette (`html.palette-warm` in the mockups'
/// `css/palette.css`, chosen 13 October 2026), with the soft-style tints and shadows from
/// `css/soft.css`. Lily only chose light appearance, so the dark values are derived here.
/// `DesignSystem/README.md` explains how, and lists the CSS source of each token.
///
/// `Resources/Colors.xcassets` must hold exactly these values. `PaletteAssetCatalogTests`
/// fails when the two drift apart, and tells you which colour set to fix.
nonisolated public enum Palette {
    public static func value(for token: ColorToken) -> TokenValue {
        switch token {
        // Interface
        case .background: TokenValue(light: RGBA(hex: 0xF4EEE6), dark: RGBA(hex: 0x211B16))
        case .backgroundLow: TokenValue(light: RGBA(hex: 0xEBE2D6), dark: RGBA(hex: 0x1B1612))
        case .surface: TokenValue(light: RGBA(hex: 0xFFFDF9), dark: RGBA(hex: 0x2E2620))
        case .tint: TokenValue(light: RGBA(hex: 0xFFFFFF, alpha: 0.55), dark: RGBA(hex: 0xFFF0E1, alpha: 0.07))
        case .tintStrong: TokenValue(light: RGBA(hex: 0xFFFFFF, alpha: 0.82), dark: RGBA(hex: 0x3A3028, alpha: 0.94))
        case .textPrimary: TokenValue(light: RGBA(hex: 0x2A211B), dark: RGBA(hex: 0xF4EEE6))
        case .textSecondary: TokenValue(light: RGBA(hex: 0x6B5E54), dark: RGBA(hex: 0xC7B8AA))
        case .accent: TokenValue(light: RGBA(hex: 0x4B3628), dark: RGBA(hex: 0xDCC3A8))
        case .accentPressed: TokenValue(light: RGBA(hex: 0x35261B), dark: RGBA(hex: 0xC4A98D))
        case .onAccent: TokenValue(light: RGBA(hex: 0xFFFFFF), dark: RGBA(hex: 0x211B16))
        case .accentSoft: TokenValue(light: RGBA(hex: 0xEFE6DB), dark: RGBA(hex: 0x3B3027))
        case .chevron: TokenValue(light: RGBA(hex: 0x8A7B6E), dark: RGBA(hex: 0x9C8C7E))
        case .track: TokenValue(light: RGBA(hex: 0xE6DCCD), dark: RGBA(hex: 0x4A3F36))
        case .divider: TokenValue(light: RGBA(hex: 0x967D64, alpha: 0.3), dark: RGBA(hex: 0xE6D2BE, alpha: 0.2))
        case .shadow: TokenValue(light: RGBA(hex: 0x3C2A1C, alpha: 0.26), dark: RGBA(hex: 0x000000, alpha: 0.55))
        case .shadowLarge: TokenValue(light: RGBA(hex: 0x3C2A1C, alpha: 0.32), dark: RGBA(hex: 0x000000, alpha: 0.6))

        // Status
        case .success: TokenValue(light: RGBA(hex: 0x46613F), dark: RGBA(hex: 0xB9CDA6))
        case .successSurface: TokenValue(light: RGBA(hex: 0xE5E9D6), dark: RGBA(hex: 0x2C3424))
        case .warning: TokenValue(light: RGBA(hex: 0x7A5B14), dark: RGBA(hex: 0xE6C98A))
        case .warningSurface: TokenValue(light: RGBA(hex: 0xF5EACB), dark: RGBA(hex: 0x433A22))
        case .error: TokenValue(light: RGBA(hex: 0xA3352B), dark: RGBA(hex: 0xF2A596))
        case .errorSurface: TokenValue(light: RGBA(hex: 0xF7E2DA), dark: RGBA(hex: 0x4A2924))

        // Room and art
        case .floor: TokenValue(light: RGBA(hex: 0xE5D7C5), dark: RGBA(hex: 0x362C24))
        case .floorLow: TokenValue(light: RGBA(hex: 0xDACAB4), dark: RGBA(hex: 0x30271F))
        case .floorLine: TokenValue(light: RGBA(hex: 0xC6B097), dark: RGBA(hex: 0x1A1410))
        case .artSage: TokenValue(light: RGBA(hex: 0xC9CDB4), dark: RGBA(hex: 0x858770))
        case .artSageDeep: TokenValue(light: RGBA(hex: 0xB6BB9E), dark: RGBA(hex: 0x787B62))
        case .artSageLine: TokenValue(light: RGBA(hex: 0x959A7C), dark: RGBA(hex: 0x62664D))
        case .artSand: TokenValue(light: RGBA(hex: 0xE3D3C6), dark: RGBA(hex: 0x968B7B))
        case .artStone: TokenValue(light: RGBA(hex: 0xDCD3CA), dark: RGBA(hex: 0x918B7D))
        case .artButter: TokenValue(light: RGBA(hex: 0xEFE3C8), dark: RGBA(hex: 0x9E967C))
        case .artButterLine: TokenValue(light: RGBA(hex: 0xCDB98F), dark: RGBA(hex: 0x877A59))
        case .signPanel: TokenValue(light: RGBA(hex: 0xFFF7EA), dark: RGBA(hex: 0xA8A391))
        case .signText: TokenValue(light: RGBA(hex: 0x4B3628), dark: RGBA(hex: 0x3A2A1E))
        case .stickerEdge: TokenValue(light: RGBA(hex: 0xFFFFFF), dark: RGBA(hex: 0xEEE7DE))
        }
    }
}
