import Foundation

/// An sRGB colour with 8-bit channels and an opacity, written the way the CSS mockups write it.
///
/// `Palette` holds every colour token as a pair of these, one per appearance. The asset catalog
/// is checked against them in the tests, and the contrast checks are computed from them.
nonisolated public struct RGBA: Hashable, Sendable, CustomStringConvertible {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    /// Opacity from 0 (clear) to 1 (opaque).
    public let alpha: Double

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Makes a colour from a CSS-style hex value, for example `RGBA(hex: 0xF4EEE6)`.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: UInt8((hex >> 16) & 0xFF),
            green: UInt8((hex >> 8) & 0xFF),
            blue: UInt8(hex & 0xFF),
            alpha: alpha
        )
    }

    /// The colour as `#RRGGBB`, with the opacity added when it isn't 1.
    public var description: String {
        let digits = [red, green, blue].map { channel in
            let text = String(channel, radix: 16, uppercase: true)
            return channel < 16 ? "0" + text : text
        }
        let hex = "#" + digits.joined()
        return alpha == 1 ? hex : "\(hex) at \(alpha)"
    }

    public var isOpaque: Bool { alpha == 1 }

    /// What you see when this colour is drawn over an opaque `base`, the way a browser
    /// or SwiftUI blends a see-through tint over the wall.
    public func composited(over base: RGBA) -> RGBA {
        func mix(_ top: UInt8, _ bottom: UInt8) -> UInt8 {
            UInt8((Double(top) * alpha + Double(bottom) * (1 - alpha)).rounded())
        }
        return RGBA(red: mix(red, base.red), green: mix(green, base.green), blue: mix(blue, base.blue))
    }

    /// WCAG 2 relative luminance of the colour, treated as opaque.
    public var relativeLuminance: Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio between two opaque colours, from 1 (same) to 21 (black on white).
    public static func contrastRatio(_ first: RGBA, _ second: RGBA) -> Double {
        let lighter = max(first.relativeLuminance, second.relativeLuminance)
        let darker = min(first.relativeLuminance, second.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
