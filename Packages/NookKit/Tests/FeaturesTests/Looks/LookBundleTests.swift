import CoreGraphics
import DesignSystem
import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// What a look bundle shows and says (Phase 9): its pieces in body order, ideas tagged, missing
/// garments left out, and one spoken summary.
@MainActor
@Suite
struct LookBundleTests {
    let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
    var garments: [Garment.ID: Garment] { Dictionary(uniqueKeysWithValues: data.garments.map { ($0.id, $0) }) }
    let english = Locale(identifier: "en_US")

    func look(_ id: Look.ID) throws -> Look {
        try #require(data.looks.first { $0.id == id })
    }

    @Test func piecesComeInBodyOrder() throws {
        let content = LookBundleContent(look: try look("o-brunch-idea"), garments: garments)
        #expect(content.id == "o-brunch-idea")
        #expect(content.name == "Brunch with a new layer")
        #expect(
            content.pieces.map(\.name) == [
                "Cropped cream cardigan", "Cute pink shirt", "Olive trousers", "Tan loafers",
            ])
        #expect(content.pieces.map(\.category) == [.layer, .top, .bottom, .shoes])
    }

    @Test func anIdeaIsTaggedAndDrawnFromItsKind() throws {
        let content = LookBundleContent(look: try look("o-brunch-idea"), garments: garments)
        let idea = try #require(content.ideas.first)
        #expect(content.ideas.count == 1)
        #expect(idea.isIdea)
        #expect(idea.photo == .noPhoto && idea.cutout == nil)
        #expect(idea.colors == [.cream])
        #expect(content.pieces.filter { !$0.isIdea }.count == 3)
    }

    @Test func aGarmentThatIsGoneIsLeftOut() throws {
        var remaining = garments
        remaining["g-navy-trousers"] = nil
        let content = LookBundleContent(look: try look("o-interview"), garments: remaining)
        #expect(content.pieces.map(\.name) == ["Navy cardigan", "Cute pink shirt", "Nude pointed flats"])
    }

    @Test func garmentPiecesKeepTheirPhotoAndCutout() {
        let photoPieces = SamplePhotoGarments.garments(now: TestTime.now)
        let content = LookBundleSamples.withPhotos(LookBundleSamples.photoPieces(from: photoPieces))
        let tee = content.pieces.first { $0.id == "g-photo-white-on-white" }
        #expect(tee?.cutout != nil)
        #expect(tee.map { GarmentArtChoice(photo: $0.photo, cutout: $0.cutout).isPhotoTile } == true)
        let skirt = content.pieces.first { $0.id == "g-photo-shiny-skirt" }
        #expect(skirt.map { GarmentArtChoice(photo: $0.photo, cutout: $0.cutout).isCutout } == true)
    }

    @Test func sameAsSimpleComesFromTheLook() throws {
        let content = LookBundleContent(look: try look("o-interview"), garments: garments)
        #expect(content.pieces.allSatisfy { $0.isSameAsSimple })
        let made = LookBundleContent(look: try look("o-lace-date"), garments: garments)
        #expect(made.pieces.allSatisfy { !$0.isSameAsSimple })
    }

    @Test func everyKindHasARole() {
        let roles = GarmentCategory.allCases.map {
            LookBundlePiece(id: $0.rawValue, name: $0.rawValue, category: $0, colors: []).role
        }
        #expect(Set(roles) == Set(BundleRole.allCases))
    }

    // MARK: Spoken

    @Test func summaryNamesThePiecesInOrder() {
        let summary = LookBundleText.summary(of: LookBundleSamples.byPieceCount[1], title: nil, locale: english)
        #expect(summary == "Look: Cream blouse, Navy trousers, Tan loafers")
    }

    @Test func summaryUsesTheTitleThenTheName() throws {
        let content = LookBundleContent(look: try look("o-interview"), garments: garments)
        #expect(
            LookBundleText.summary(of: content, title: nil, locale: english)
                == "Interview navy and pink: Navy cardigan, Cute pink shirt, Navy dress pants, Nude pointed flats")
        #expect(
            LookBundleText.summary(of: content, title: "Look 2", locale: english).hasPrefix("Look 2: Navy cardigan"))
    }

    @Test func summarySaysWhichPieceSheDoesNotOwn() {
        let summary = LookBundleText.summary(
            of: LookBundleSamples.somethingNew, title: "Something new", locale: english)
        #expect(
            summary
                == "Something new: Camel blazer (not in your closet), Cream blouse, Navy trousers, Tan loafers")
    }

    @Test func summaryOfALookWithNothingLeft() {
        let summary = LookBundleText.summary(
            of: LookBundleContent(id: "empty", pieces: []), title: nil, locale: english)
        #expect(summary == "Look: no pieces")
    }

    // MARK: The idea tag

    @Test func tagIsCentredOnItsPointWhenThereIsRoom() {
        let origin = BundleTagLayout.origin(
            for: CGSize(width: 100, height: 24), centredOn: CGPoint(x: 150, y: 100), in: CGSize(width: 300, height: 356)
        )
        #expect(origin == CGPoint(x: 100, y: 88))
    }

    @Test func tagStaysInsideTheBundle() {
        let bounds = CGSize(width: 300, height: 356)
        let size = CGSize(width: 140, height: 24)
        let left = BundleTagLayout.origin(for: size, centredOn: CGPoint(x: 10, y: 5), in: bounds)
        #expect(left == CGPoint(x: 0, y: 0))
        let right = BundleTagLayout.origin(for: size, centredOn: CGPoint(x: 295, y: 350), in: bounds)
        #expect(right == CGPoint(x: 160, y: 332))
        let tooWide = BundleTagLayout.origin(for: CGSize(width: 400, height: 24), centredOn: .zero, in: bounds)
        #expect(tooWide.x == 0)
    }

    // MARK: Sizes

    @Test func sizesKeepTheMockupShape() {
        #expect(abs(LookBundleSize.large.height - 356) < 0.001)
        #expect(abs(LookBundleSize.small.height - 64 * 356 / 300) < 0.001)
        #expect(LookBundleSize.small.isThumbnail)
        #expect(!LookBundleSize.medium.isThumbnail && !LookBundleSize.large.isThumbnail)
    }

    /// Thumbnails share stickers: the same kind and colours at the same size is one sticker,
    /// whichever look it's in, so a list of looks makes few.
    @Test func thumbnailsOfOneOutfitShareStickerNames() {
        let names = LookBundleSamples.versions.flatMap { version in
            version.content.pieces.filter { !$0.isIdea }.map {
                GarmentPicture.drawingSticker(category: $0.category, colors: $0.colors).id
            }
        }
        #expect(Set(names).count < names.count)
    }
}

extension GarmentArtChoice {
    fileprivate var isPhotoTile: Bool {
        if case .photoTile = self { true } else { false }
    }

    fileprivate var isCutout: Bool {
        if case .cutout = self { true } else { false }
    }
}
