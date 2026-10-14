import Testing

@testable import DesignSystem

struct PaletteTests {
    /// Tokens that take a `palette-warm` value straight from `css/palette.css`, unchanged.
    static let warmPaletteLightValues: [ColorToken: UInt32] = [
        .background: 0xF4EEE6,  // --wall
        .backgroundLow: 0xEBE2D6,  // --wall-2
        .surface: 0xFFFDF9,  // --plate
        .textPrimary: 0x2A211B,  // --ink
        .textSecondary: 0x6B5E54,  // --ink-soft
        .accent: 0x4B3628,  // --plum, espresso in palette-warm
        .accentPressed: 0x35261B,  // --plum-2
        .accentSoft: 0xEFE6DB,  // --plum-soft
        .track: 0xE6DCCD,  // --plate-line
        .floor: 0xE5D7C5,  // --floor
        .floorLow: 0xDACAB4,  // --floor-2
        .floorLine: 0xC6B097,  // --floor-line
        .artSage: 0xC9CDB4,  // --sage
        .artSageDeep: 0xB6BB9E,  // --sage-2
        .artSageLine: 0x959A7C,  // --sage-line
        .artSand: 0xE3D3C6,  // --pink
        .artStone: 0xDCD3CA,  // --lilac
        .artButter: 0xEFE3C8,  // --butter
        .artButterLine: 0xCDB98F,  // --butter-line
    ]

    @Test(arguments: warmPaletteLightValues.keys.sorted { $0.rawValue < $1.rawValue })
    func lightValueMatchesWarmPalette(token: ColorToken) throws {
        let expected = try #require(Self.warmPaletteLightValues[token])
        #expect(token.value.light == RGBA(hex: expected))
    }

    @Test func softStyleTintsAndShadowsMatchTheCSS() {
        #expect(ColorToken.tint.value.light == RGBA(hex: 0xFFFFFF, alpha: 0.55))  // --soft-tint
        #expect(ColorToken.tintStrong.value.light == RGBA(hex: 0xFFFFFF, alpha: 0.82))  // --soft-tint-strong
        #expect(ColorToken.shadow.value.light == RGBA(hex: 0x3C2A1C, alpha: 0.26))  // palette-warm --soft-drop
        #expect(ColorToken.shadowLarge.value.light == RGBA(hex: 0x3C2A1C, alpha: 0.32))  // --soft-drop-lg
        #expect(ColorToken.divider.value.light == RGBA(hex: 0x967D64, alpha: 0.3))  // --soft-divider
        #expect(ColorToken.onAccent.value.light == RGBA(hex: 0xFFFFFF))
    }

    /// LR-02.1: no plum or pink values remain. These are every plum and pink value in the old
    /// `room.css`, `soft.css` and `dark.css`.
    @Test func noPlumOrPinkValuesRemain() {
        let retired: Set<UInt32> = [
            0x6A1F58, 0x4F1541, 0xF6E3F0, 0xFBE5E8, 0xF7D6DC, 0xF6DDD2, 0xEFCFC2, 0xE3BBAE, 0xF4B4C2, 0xEC9DB0,
            0xD97F97, 0xE9D9E2, 0x2B1B27, 0x6B5563, 0xF1E6EC, 0xD9CDD5, 0xFCE6F2, 0x9A8291, 0xF2B6DF, 0xE29BCB,
            0x4E3046, 0x7E3570, 0x64295A, 0x3A2A33, 0x32242C, 0x45323A, 0x3D2C33, 0x2A1D24, 0xF6EAF0, 0xCDB8C5,
            0x3F2E39, 0x4A3542, 0x5E4656, 0x5A3A4E, 0xBFA5B5, 0x633B55, 0xD9AFCB, 0xF0E0E5, 0x432F3D,
        ]
        for token in ColorToken.allCases {
            for appearance in Appearance.allCases {
                let value = token.value[appearance]
                let hex = UInt32(value.red) << 16 | UInt32(value.green) << 8 | UInt32(value.blue)
                #expect(
                    !retired.contains(hex), "\(token.rawValue) (\(appearance.rawValue)) uses an old plum or pink value")
            }
        }
    }

    /// The dark room is the same room at night: wall and floor go dark, and drawn art is
    /// dimmed but never brighter than in daylight.
    @Test(arguments: ColorToken.allCases.filter { $0.group == .room })
    func roomIsDimmerAtNight(token: ColorToken) {
        #expect(token.value.dark.relativeLuminance < token.value.light.relativeLuminance)
    }

    /// Dark values stay warm: red at least as strong as blue, so nothing drifts grey-blue.
    /// Shadows are pure black and are left out.
    @Test(arguments: ColorToken.allCases.filter { ![.shadow, .shadowLarge].contains($0) })
    func darkValuesStayWarm(token: ColorToken) {
        let dark = token.value.dark
        #expect(dark.red >= dark.blue, "\(token.rawValue) dark \(dark) leans blue")
    }

    @Test func everyTokenHasAGroup() {
        let grouped = ColorToken.Group.allCases.flatMap { group in ColorToken.allCases.filter { $0.group == group } }
        #expect(grouped.count == ColorToken.allCases.count)
    }
}
