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

/// Look bundles (Phase 9), compared with the PNGs in `__Snapshots__/LookBundleSnapshotTests`.
///
/// - 2, 3, 4, 5 and 6 pieces and Something new, each large beside its thumbnail, on a phone
///   (402 points) and an iPad (820 points).
/// - The catalog page on a phone: a large bundle with its piece list, medium bundles of 2 to 6
///   pieces, a dress look, Something new with its list and Find one, and tappable thumbnails, in
///   light, dark and AX5.
/// - Her photos mixed with drawn pieces: a clean cutout as a sticker and a photo tile, light
///   and dark.
@MainActor
@Suite(.heavyMainActorWork)
struct LookBundleSnapshotTests {
    static let phone: CGFloat = 402
    static let iPad: CGFloat = 820
    static let scale: CGFloat = 1

    @Test func piecesPhone() {
        assertSnapshot(countsBoard(columns: 1), width: Self.phone, named: "pieces-phone")
    }

    @Test func piecesIPad() {
        assertSnapshot(countsBoard(columns: 2), width: Self.iPad, sizeClass: .regular, named: "pieces-ipad")
    }

    @Test func catalogPage() {
        assertSnapshot(
            LookBundleDemo(photoGarments: []).padding(NookSpacing.large), width: Self.phone, named: "catalog")
    }

    @Test func catalogPageDark() {
        assertSnapshot(
            LookBundleDemo(photoGarments: []).padding(NookSpacing.large), width: Self.phone, colorScheme: .dark,
            named: "catalog-dark")
    }

    /// The bundles don't change with text size; the piece list and the tag do (the tag stops
    /// at xxLarge).
    @Test func catalogPageAX5() {
        assertSnapshot(
            LookBundleDemo(photoGarments: []).padding(NookSpacing.large), width: Self.phone,
            dynamicTypeSize: .accessibility5, named: "catalog-ax5")
    }

    /// The "Not in your closet" tag stays on one line: across a bundle too narrow for that, as on
    /// a Saved Looks card on iPad, it's the thumbnails' round icon instead of two lines over the
    /// picture (QA, October 2026). No picture: the tag is too small a part of any page for a
    /// snapshot to notice the change.
    @Test func ideaTagIsOneLineOrTheIcon() {
        let words = fittedWidth(of: IdeaTag(), width: 300)
        let oneLine = fittedWidth(of: Text(LookBundleText.notInYourCloset).nookTextStyle(.caption), width: 1000)
        #expect(words > oneLine)
        #expect(fittedWidth(of: IdeaTag(), width: words - 1) == 24)
        #expect(fittedWidth(of: IdeaTag(), width: 120) == 24)
    }

    @Test func photosMixedIn() async {
        let look = photoLook
        let loader = await loadedPictures(for: look, sizes: [.large, .small])
        assertSnapshot(photoBoard(look), width: Self.phone, loader: loader, named: "photos")
    }

    @Test func photosMixedInDark() async {
        let look = photoLook
        let loader = await loadedPictures(for: look, sizes: [.large, .small])
        assertSnapshot(photoBoard(look), width: Self.phone, loader: loader, colorScheme: .dark, named: "photos-dark")
    }

    // MARK: Boards

    /// Each look large with its thumbnail beside it, `columns` to a row.
    private func countsBoard(columns: Int) -> some View {
        let looks = LookBundleSamples.byPieceCount + [LookBundleSamples.somethingNew]
        return VStack(alignment: .leading, spacing: NookSpacing.large) {
            ForEach(Array(stride(from: 0, to: looks.count, by: columns)), id: \.self) { start in
                HStack(alignment: .top, spacing: NookSpacing.xxLarge) {
                    ForEach(looks[start..<min(start + columns, looks.count)]) { look in
                        HStack(alignment: .bottom, spacing: NookSpacing.small) {
                            LookBundle(look, size: .large)
                            LookBundle(look, size: .small)
                        }
                    }
                }
            }
        }
        .padding(NookSpacing.medium)
    }

    private var photoLook: LookBundleContent {
        LookBundleSamples.withPhotos(
            LookBundleSamples.photoPieces(from: SamplePhotoGarments.garments(now: TestTime.now)))
    }

    private func photoBoard(_ look: LookBundleContent) -> some View {
        HStack(alignment: .bottom, spacing: NookSpacing.small) {
            LookBundle(look, size: .large)
            LookBundle(look, size: .small)
        }
        .padding(NookSpacing.medium)
    }

    /// A loader with every photo and cutout the look needs at these bundle sizes, since a still
    /// image can't wait for one. The sizes are worked out the way the bundle works them out.
    private func loadedPictures(for look: LookBundleContent, sizes: [LookBundleSize]) async -> GarmentImageLoader {
        let loader = GarmentImageLoader(provider: SamplePhotoProvider())
        let placements = StickerBundleLayout.place(look.pieces.map(\.bundleItem), seed: look.id)
        for size in sizes {
            for placement in placements {
                let piece = look.pieces[placement.index]
                if let picture = GarmentPicture.pictureToLoad(
                    for: GarmentArtChoice(photo: piece.photo, cutout: piece.cutout),
                    size: placement.frame(forWidth: size.width).size, scale: Self.scale)
                {
                    _ = await loader.image(for: picture.reference, maxPixelSize: picture.pixelSize)
                }
            }
        }
        return loader
    }

    private func assertSnapshot(
        _ view: some View,
        width: CGFloat,
        loader: GarmentImageLoader? = nil,
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        sizeClass: UserInterfaceSizeClass = .compact,
        named name: String,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let content =
            view
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.nook.wallGradient)
            .environment(\.garmentImages, loader)
            .environment(\.stickerCache, StickerCache())
            .environment(\.closetIsStillImage, true)
            .environment(\.nookStaticRendering, true)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.horizontalSizeClass, sizeClass)
            .environment(\.displayScale, Self.scale)
            .environment(\.locale, TestTime.locale)
        guard
            let image = stillImage(
                of: content, scale: Self.scale, proposedSize: ProposedViewSize(width: width, height: nil))
        else {
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
