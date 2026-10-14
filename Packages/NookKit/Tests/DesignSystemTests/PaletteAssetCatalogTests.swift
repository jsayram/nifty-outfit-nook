import Foundation
import SwiftUI
import Testing

@testable import DesignSystem

/// `Palette.swift` is the source of truth. These tests fail when `Colors.xcassets` drifts from it.
@MainActor
struct PaletteAssetCatalogTests {
    /// Reads the catalog's source files next to this test. Simulator tests can read the Mac's
    /// file system, which is where CI runs them.
    static let catalogURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../Sources/DesignSystem/Resources/Colors.xcassets")
        .standardized

    @Test func catalogHasExactlyOneColourSetPerToken() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.catalogURL.path(percentEncoded: false))
            .filter { $0.hasSuffix(".colorset") }
            .map { String($0.dropLast(".colorset".count)) }
        #expect(Set(names) == Set(ColorToken.allCases.map(\.assetName)))
        #expect(names.count == ColorToken.allCases.count)
    }

    @Test(arguments: ColorToken.allCases)
    func colourSetMatchesPalette(token: ColorToken) throws {
        let url = Self.catalogURL.appending(path: "\(token.assetName).colorset/Contents.json")
        let colourSet = try JSONDecoder().decode(ColourSet.self, from: Data(contentsOf: url))

        let anyAppearance = colourSet.colors.filter { $0.appearances == nil }
        let dark = colourSet.colors.filter {
            $0.appearances?.contains(.init(appearance: "luminosity", value: "dark")) == true
        }
        #expect(colourSet.colors.count == 2, "\(token.assetName) should have only an Any and a Dark entry")
        try #require(anyAppearance.count == 1 && dark.count == 1)

        for (entry, expected) in [(anyAppearance[0], token.value.light), (dark[0], token.value.dark)] {
            #expect(entry.idiom == "universal")
            #expect(entry.color.colorSpace == "srgb")
            let actual = try entry.color.components.rgba()
            #expect(actual == expected, "\(token.assetName).colorset has \(actual), Palette.swift says \(expected)")
        }
    }

    /// The compiled catalog in the module's bundle resolves to the palette values through `Color.nook`,
    /// in both appearances.
    @Test(arguments: ColorToken.allCases)
    func colourResolvesToPaletteValues(token: ColorToken) {
        for appearance in Appearance.allCases {
            var environment = EnvironmentValues()
            environment.colorScheme = appearance == .dark ? .dark : .light
            let resolved = Color(token: token).resolve(in: environment)
            let expected = token.value[appearance]

            // Color.Resolved stores linear sRGB, so compare in the same space, allowing for rounding.
            func linear(_ channel: UInt8) -> Float {
                let value = Float(channel) / 255
                return value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let tolerance: Float = 0.004
            #expect(abs(resolved.linearRed - linear(expected.red)) < tolerance, "\(token) \(appearance) red")
            #expect(abs(resolved.linearGreen - linear(expected.green)) < tolerance, "\(token) \(appearance) green")
            #expect(abs(resolved.linearBlue - linear(expected.blue)) < tolerance, "\(token) \(appearance) blue")
            #expect(abs(Double(resolved.opacity) - expected.alpha) < 0.003, "\(token) \(appearance) opacity")
        }
    }
}

// MARK: - The colour set file format

private struct ColourSet: Decodable {
    let colors: [Entry]

    struct Entry: Decodable {
        let appearances: [AppearanceEntry]?
        let color: ColourValue
        let idiom: String
    }

    struct AppearanceEntry: Decodable, Equatable {
        let appearance: String
        let value: String
    }

    struct ColourValue: Decodable {
        let colorSpace: String
        let components: Components

        enum CodingKeys: String, CodingKey {
            case colorSpace = "color-space"
            case components
        }
    }

    struct Components: Decodable {
        let red: String
        let green: String
        let blue: String
        let alpha: String

        struct BadValue: Error {
            let text: String
        }

        /// Channels are written as "0xF4", the opacity as "0.550".
        func rgba() throws -> RGBA {
            func channel(_ text: String) throws -> UInt8 {
                guard text.hasPrefix("0x"), let value = UInt8(text.dropFirst(2), radix: 16) else {
                    throw BadValue(text: text)
                }
                return value
            }
            guard let opacity = Double(alpha) else { throw BadValue(text: alpha) }
            return RGBA(red: try channel(red), green: try channel(green), blue: try channel(blue), alpha: opacity)
        }
    }
}
