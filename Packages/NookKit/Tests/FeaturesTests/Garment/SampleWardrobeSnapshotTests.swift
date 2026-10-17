import DesignSystem
import Fixtures
import Models
import NookTestSupport
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// The sample wardrobe's real photos on screen, compared with the PNGs in
/// `__Snapshots__/SampleWardrobeSnapshotTests`. Drawn 402 points wide at 1x, with every picture
/// loaded first, since a still image can't wait for one.
///
/// - The demo pieces standing on the floor as in Closet (cutouts, and the lace tops as photo
///   tiles), in light and dark.
/// - The 30 extras of `wardrobe=full`.
/// - Try-on pictures with a sample preview, beside one drawn from its pieces, and the example
///   try-on photo.
@MainActor
@Suite(.heavyMainActorWork)
struct SampleWardrobeSnapshotTests {
    static let width: CGFloat = 402
    static let scale: CGFloat = 1
    static let cell = CGSize(width: 84, height: 108)

    private func services(_ configuration: FixtureConfiguration = FixtureConfiguration()) -> NookServices {
        FixtureServices.make(configuration, now: TestTime.now, calendar: TestTime.calendar)
    }

    private func demoGarments() async throws -> [Garment] {
        try await services().closet.garments().filter { $0.id != "g-gray-leggings" }
    }

    @Test func demoPieces() async throws {
        let garments = try await demoGarments()
        let loader = await loadedPictures(for: garments, sizes: [Self.cell])
        assertSnapshot(grid(garments), loader: loader, named: "demo")
    }

    @Test func demoPiecesDark() async throws {
        let garments = try await demoGarments()
        let loader = await loadedPictures(for: garments, sizes: [Self.cell])
        assertSnapshot(grid(garments), loader: loader, colorScheme: .dark, named: "demo-dark")
    }

    @Test func fullWardrobeExtras() async throws {
        let ids = Set(try await services().closet.garments().map(\.id))
        let extras = try await services(FixtureConfiguration(wardrobe: .full)).closet.garments()
            .filter { !ids.contains($0.id) }
        let loader = await loadedPictures(for: extras, sizes: [Self.cell])
        assertSnapshot(grid(extras), loader: loader, named: "extras")
    }

    @Test func tryOnPictures() async throws {
        let services = services()
        let garments = Dictionary(uniqueKeysWithValues: try await services.closet.garments().map { ($0.id, $0) })
        let pictures = try await services.pictures.pictures()
        let office = try #require(pictures.first { $0.id == "p-office" })
        let weekend = try #require(pictures.first { $0.id == "p-weekend" })
        let drawn = try #require(pictures.first { $0.id == "p-lace" })
        let width: CGFloat = 112
        let loader = GarmentImageLoader(provider: SampleWardrobeProvider())
        for picture in [office, weekend] {
            if case .generated(let photo) = picture.image {
                _ = await loader.image(for: photo, maxPixelSize: Int(width * 1.25 * Self.scale))
                _ = await loader.image(for: photo, maxPixelSize: Int(ExamplePhoto.size.height * Self.scale))
            }
        }
        _ = await loader.image(for: SampleWardrobe.person, maxPixelSize: Int(ExamplePhoto.size.height * Self.scale))
        assertSnapshot(
            VStack(spacing: NookSpacing.large) {
                HStack(alignment: .top, spacing: NookSpacing.medium) {
                    ForEach([office, weekend, drawn]) { picture in
                        TryOnPictureView(
                            content: LookBundleContent(picture: picture, garments: garments), lookName: "Look",
                            width: width)
                    }
                }
                ExamplePhoto()
            }
            .padding(NookSpacing.medium)
            .environment(\.scenePhase, .active), loader: loader, named: "try-on")
    }

    // MARK: Helpers

    private func grid(_ garments: [Garment]) -> some View {
        NookFlowLayout(spacing: NookSpacing.medium, lineSpacing: NookSpacing.medium) {
            ForEach(garments) { garment in
                GarmentPicture(garment, size: Self.cell, presentation: .standing)
            }
        }
        .padding(NookSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nook.floor)
    }

    private func loadedPictures(for garments: [Garment], sizes: [CGSize]) async -> GarmentImageLoader {
        let loader = GarmentImageLoader(provider: SampleWardrobeProvider())
        for garment in garments {
            for size in sizes {
                if let picture = GarmentPicture.pictureToLoad(
                    for: GarmentArtChoice(garment), size: size, scale: Self.scale)
                {
                    _ = await loader.image(for: picture.reference, maxPixelSize: picture.pixelSize)
                }
            }
        }
        return loader
    }

    private func assertSnapshot(
        _ view: some View,
        loader: GarmentImageLoader?,
        colorScheme: ColorScheme = .light,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let content =
            view
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.nook.floor)
            .environment(\.garmentImages, loader)
            .environment(\.stickerCache, StickerCache())
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, Self.scale)
            .environment(\.locale, TestTime.locale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = Self.scale
        renderer.proposedSize = ProposedViewSize(width: Self.width, height: nil)
        guard let image = renderer.uiImage else {
            Issue.record("ImageRenderer produced no image for \(name)")
            return
        }
        SnapshotTesting.assertSnapshot(
            of: image,
            as: .image(precision: 0.995, perceptualPrecision: 0.98, scale: Self.scale),
            named: name,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}
