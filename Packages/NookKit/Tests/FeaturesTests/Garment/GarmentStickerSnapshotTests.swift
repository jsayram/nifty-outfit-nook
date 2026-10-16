import DesignSystem
import Fixtures
import Models
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import DesignSystem
@testable import Features

/// Garments as stickers and photo tiles (Phase 8b), compared with the PNGs in
/// `__Snapshots__/GarmentStickerSnapshotTests`. Drawn 402 points wide on the floor colour.
///
/// - Demo pieces (drawings) as stickers at detail and closet sizes, every kind, in light and dark.
/// - The eight sample photos from `-fixtures demo:photos=samples`: six cutouts as stickers and two
///   photo tiles, in light and dark.
/// - Garment detail with a sample photo's sticker, and with a tile.
@MainActor
@Suite(.heavyMainActorWork)
struct GarmentStickerSnapshotTests {
    static let width: CGFloat = 402
    static let scale: CGFloat = 2

    /// Every kind of piece: demo pieces, plus a made-up hat and a multicolour scarf-top, which
    /// the demo closet doesn't have.
    private var drawings: [Garment] {
        let data = FixtureSet.demo.data(now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
        let ids: [Garment.ID] = [
            "g-pink-blouse", "g-navy-trousers", "g-blue-dress", "g-brown-jacket", "g-tan-loafers", "g-burgundy-bag",
            "g-black-tee", "g-wide-jeans", "g-white-sneakers",
        ]
        let demo = ids.compactMap { id in data.garments.first { $0.id == id } }
        return demo + [
            Garment(
                id: "g-test-hat", name: "Straw hat", category: .accessory, colors: [.beige], addedAt: ClosetTestTime.now
            ),
            Garment(
                id: "g-test-stripes", name: "Rainbow top", category: .top, colors: [.multicolor],
                addedAt: ClosetTestTime.now),
        ]
    }

    @Test func drawingsAsStickers() {
        assertSnapshot(board(drawings), named: "drawings")
    }

    @Test func drawingsAsStickersDark() {
        assertSnapshot(board(drawings), colorScheme: .dark, named: "drawings-dark")
    }

    @Test func samplePhotos() async {
        let garments = SamplePhotoGarments.garments(now: ClosetTestTime.now)
        let loader = await loadedPictures(for: garments, sizes: [Self.large, Self.small])
        assertSnapshot(board(garments), loader: loader, named: "sample-photos")
    }

    @Test func samplePhotosDark() async {
        let garments = SamplePhotoGarments.garments(now: ClosetTestTime.now)
        let loader = await loadedPictures(for: garments, sizes: [Self.large, Self.small])
        assertSnapshot(board(garments), loader: loader, colorScheme: .dark, named: "sample-photos-dark")
    }

    /// Garment detail with a photo: the striped sweater as a sticker, the white tee as a tile.
    @Test func detailWithAPhoto() async throws {
        let garments = SamplePhotoGarments.garments(now: ClosetTestTime.now)
        let sweater = try #require(garments.first { $0.id == "g-photo-striped-sweater" })
        let whiteTee = try #require(garments.first { $0.id == "g-photo-white-on-white" })
        let stage = CGSize(width: 190, height: 236)
        let loader = await loadedPictures(for: [sweater, whiteTee], sizes: [stage])
        assertSnapshot(
            VStack(spacing: 0) {
                GarmentStage(garment: sweater, isInTheWash: false)
                GarmentStage(garment: whiteTee, isInTheWash: false)
            }
            .padding(.vertical, NookSpacing.large)
            .background(Color.nook.wallGradient),
            loader: loader, named: "detail-photos")
    }

    // MARK: Board

    static let large = CGSize(width: 110, height: 140)
    static let small = CGSize(width: 70, height: 90)

    /// Three pieces a row at detail-like size, then a row of small ones, on the floor.
    private func board(_ garments: [Garment]) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            ForEach(Array(stride(from: 0, to: garments.count, by: 3)), id: \.self) { start in
                HStack(alignment: .top, spacing: NookSpacing.large) {
                    ForEach(garments[start..<min(start + 3, garments.count)]) { garment in
                        GarmentPicture(garment, size: Self.large, presentation: .sticker(.centred))
                            .rotationEffect(.degrees(-3))
                    }
                }
            }
            NookFlowLayout(spacing: NookSpacing.medium, lineSpacing: NookSpacing.medium) {
                ForEach(garments) { garment in
                    GarmentPicture(garment, size: Self.small, presentation: .sticker(.centred))
                }
            }
        }
        .padding(NookSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nook.floor)
    }

    /// A loader with every picture these garments need at these sizes already loaded, since a
    /// still image can't wait for one.
    private func loadedPictures(for garments: [Garment], sizes: [CGSize]) async -> GarmentImageLoader {
        let loader = GarmentImageLoader(provider: SamplePhotoProvider())
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
        loader: GarmentImageLoader? = nil,
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
            .environment(\.garmentImages, loader)
            .environment(\.stickerCache, StickerCache())
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.displayScale, Self.scale)
            .environment(\.locale, ClosetTestTime.locale)
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
