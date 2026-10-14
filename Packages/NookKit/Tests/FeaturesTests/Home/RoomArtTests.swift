import DesignSystem
import Foundation
import Testing
import UIKit

@testable import Features

/// The room art in `Room.xcassets`: every drawing loads in light and dark, keeps its vector
/// data, and uses the warm palette (LR-02.3). How the art is made is in `art/room/README.md`.
@MainActor
struct RoomArtTests {
    static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()  // Home
        .deletingLastPathComponent()  // FeaturesTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // NookKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()
    static let catalog = repoRoot.appending(path: "Packages/NookKit/Sources/Features/Resources/Room.xcassets")

    @Test(arguments: RoomArt.allCases)
    func drawingLoadsInBothAppearances(art: RoomArt) throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let image = try #require(
                UIImage(named: art.rawValue, in: .module, compatibleWith: traits),
                "\(art.rawValue) is missing in \(style == .dark ? "dark" : "light")")
            #expect(image.size.width > 0 && image.size.height > 0)
        }
    }

    @Test func catalogHasExactlyTheDrawingsTheCodeNames() throws {
        let sets = try FileManager.default.contentsOfDirectory(atPath: Self.catalog.path())
            .filter { $0.hasSuffix(".imageset") }
            .map { String($0.dropLast(".imageset".count)) }
        #expect(Set(sets) == Set(RoomArt.allCases.map(\.rawValue)))
    }

    /// Single scale with vector data kept, and a dark appearance for each.
    @Test(arguments: RoomArt.allCases)
    func imageSetKeepsVectorDataWithADarkVersion(art: RoomArt) throws {
        let url = Self.catalog.appending(path: "\(art.rawValue).imageset/Contents.json")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let properties = json["properties"] as? [String: Any]
        #expect(properties?["preserves-vector-representation"] as? Bool == true)
        let images = try #require(json["images"] as? [[String: Any]])
        #expect(images.count == 2)
        #expect(images.allSatisfy { ($0["filename"] as? String)?.hasSuffix(".svg") == true })
        #expect(images.contains { ($0["appearances"] as? [[String: String]])?.first?["value"] == "dark" })
    }

    /// Dark is the light drawing in lamplight: the same shapes, each colour dimmed by the rule in
    /// DesignSystem/README.md. Garments are only dimmed to 92%, since they stand for real clothes.
    @Test(arguments: RoomArt.allCases)
    func darkIsTheLightDrawingDimmed(art: RoomArt) throws {
        let folder = Self.catalog.appending(path: "\(art.rawValue).imageset")
        let light = try String(contentsOf: folder.appending(path: "\(art.rawValue).svg"), encoding: .utf8)
        let dark = try String(contentsOf: folder.appending(path: "\(art.rawValue)-dark.svg"), encoding: .utf8)
        let lightColours = Self.hexColours(in: light)
        let darkColours = Self.hexColours(in: dark)
        #expect(Self.removingHexColours(light) == Self.removingHexColours(dark), "The two drawings differ in shape")
        #expect(lightColours.count == darkColours.count)
        let factors: [Double] = art == .wardrobeRail ? [0.92, 0.92, 0.92] : [0.66, 0.66, 0.62]
        for (lightColour, darkColour) in zip(lightColours, darkColours) {
            let expected = zip(lightColour.channels, factors).map { UInt8(($0 * $1).rounded()) }
            #expect(darkColour.bytes == expected, "\(art.rawValue): \(lightColour.text) should dim to \(expected)")
        }
    }

    /// Mockup palette colours that have a design token become exactly that token, so the room
    /// and the interface agree (LR-02.3).
    @Test func tokenColoursMatchThePalette() throws {
        let map = try #require(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: Self.repoRoot.appending(path: "art/room/palette-map.json")))
                as? [String: [String: String]])
        let tokens: [String: ColorToken] = [
            "artSage": .artSage, "artSageDeep": .artSageDeep, "artSageLine": .artSageLine, "artSand": .artSand,
            "artStone": .artStone, "artButter": .artButter, "artButterLine": .artButterLine,
            "signPanel": .signPanel, "accent": .accent,
        ]
        var checked = 0
        for (source, entry) in map {
            guard let name = entry["token"] else { continue }
            let token = try #require(tokens[name], "Unknown token \(name) for \(source)")
            let light = try #require(entry["light"])
            #expect(Self.hex(Palette.value(for: token).light) == light, "\(source) should be \(name)")
            checked += 1
        }
        #expect(checked >= 8, "The art should use the room tokens")
    }

    /// Every colour in a room drawing (not a garment) came through the palette map.
    @Test func everyRoomColourIsMapped() throws {
        let map = try #require(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: Self.repoRoot.appending(path: "art/room/palette-map.json")))
                as? [String: [String: String]])
        let mapped = Set(map.values.compactMap { $0["light"] })
        for art in RoomArt.allCases where art != .wardrobeRail {
            let url = Self.catalog.appending(path: "\(art.rawValue).imageset/\(art.rawValue).svg")
            for colour in Self.hexColours(in: try String(contentsOf: url, encoding: .utf8)) {
                #expect(mapped.contains(colour.text), "\(art.rawValue) has \(colour.text), which isn't from the map")
            }
        }
    }

    // MARK: - Helpers

    struct Hex {
        let text: String
        var bytes: [UInt8] {
            let value = UInt32(text.dropFirst(), radix: 16) ?? 0
            return [UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        }
        var channels: [Double] { bytes.map(Double.init) }
    }

    static func hexColours(in svg: String) -> [Hex] {
        svg.matches(of: /#[0-9A-Fa-f]{6}\b/).map { Hex(text: String($0.output).uppercased()) }
    }

    static func removingHexColours(_ svg: String) -> String {
        svg.replacing(/#[0-9A-Fa-f]{6}\b/, with: "#")
    }

    static func hex(_ colour: RGBA) -> String {
        String(format: "#%02X%02X%02X", colour.red, colour.green, colour.blue)
    }
}
