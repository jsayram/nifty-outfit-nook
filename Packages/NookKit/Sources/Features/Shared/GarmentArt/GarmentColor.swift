import DesignSystem
import Models
import SwiftUI

/// The colour a garment's colour family is drawn in, for its placeholder picture and its swatch.
///
/// These stand for her real clothes, so they keep their own colours instead of the room's
/// palette (LR-02: "Garments keep their real colours"). In dark appearance they're dimmed to 92%,
/// as the garments in the room art are (`art/room/README.md`).
nonisolated struct GarmentColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        red = Double(hex >> 16 & 0xFF) / 255
        green = Double(hex >> 8 & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The fill for a colour family. `multicolor` has no single colour; it draws as stripes of
    /// `multicolorStripes`.
    static func fill(for name: ColorName) -> GarmentColor {
        switch name {
        case .black: GarmentColor(hex: 0x2E2A30)
        case .white: GarmentColor(hex: 0xFAF8F4)
        case .cream: GarmentColor(hex: 0xF4E8D3)
        case .beige: GarmentColor(hex: 0xE2CDB1)
        case .tan: GarmentColor(hex: 0xC49A6C)
        case .brown: GarmentColor(hex: 0x7A4B2E)
        case .gray: GarmentColor(hex: 0xA2A4AC)
        case .navy: GarmentColor(hex: 0x27335F)
        case .blue: GarmentColor(hex: 0x8FB3E3)
        case .denim: GarmentColor(hex: 0x6F93C4)
        case .green: GarmentColor(hex: 0x5E9A6A)
        case .olive: GarmentColor(hex: 0x7C8450)
        case .red: GarmentColor(hex: 0xC2413B)
        case .brick: GarmentColor(hex: 0xB5533C)
        case .burgundy: GarmentColor(hex: 0x7B2338)
        case .pink: GarmentColor(hex: 0xF4B4C2)
        case .purple: GarmentColor(hex: 0x8C6BB1)
        case .yellow: GarmentColor(hex: 0xEDCB61)
        case .orange: GarmentColor(hex: 0xE38B45)
        case .multicolor: GarmentColor(hex: 0xE9A9B8)
        }
    }

    /// What a `multicolor` piece is drawn with.
    static let multicolorStripes: [GarmentColor] = [
        GarmentColor(hex: 0xE9A9B8), GarmentColor(hex: 0xEDCB61), GarmentColor(hex: 0x8FB3E3),
        GarmentColor(hex: 0x9CC3A0),
    ]

    /// A piece with no colour recorded is drawn in a quiet stone, so it never looks like a real colour.
    static let unknown = GarmentColor(hex: 0xCFC4B8)

    /// Relative luminance (WCAG), used to pick a line colour that shows on the fill.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The outline and fold lines: the same colour, darker. Very dark cloth gets a lighter line
    /// instead, so its shape still reads on a dark floor.
    var line: GarmentColor {
        luminance < 0.03 ? scaled(1.9, lift: 0.08) : scaled(0.68)
    }

    /// A lighter version for highlights.
    var highlight: GarmentColor { mixed(with: GarmentColor(red: 1, green: 1, blue: 1), amount: 0.28) }

    /// The colour in an appearance: real colours in light, dimmed to 92% in dark.
    func color(in scheme: ColorScheme) -> Color {
        let factor = scheme == .dark ? 0.92 : 1
        return Color(.sRGB, red: red * factor, green: green * factor, blue: blue * factor)
    }

    func scaled(_ factor: Double, lift: Double = 0) -> GarmentColor {
        GarmentColor(
            red: min(1, red * factor + lift), green: min(1, green * factor + lift), blue: min(1, blue * factor + lift))
    }

    func mixed(with other: GarmentColor, amount: Double) -> GarmentColor {
        GarmentColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount)
    }
}
