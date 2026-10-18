import Foundation
import ImageIO
import Models
import NookTestSupport
import Testing

@testable import Fixtures

/// The sample wardrobe: real photos and cutouts for the demo, the full wardrobe, the large closet
/// and the try-on previews.
struct SampleWardrobeTests {
    private func services(_ configuration: FixtureConfiguration) -> NookServices {
        FixtureServices.make(configuration, now: TestTime.now, calendar: TestTime.calendar)
    }

    private func isImage(_ data: Data?, hasAlpha: Bool? = nil) -> Bool {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            (properties[kCGImagePropertyPixelWidth] as? Int ?? 0) > 0
        else { return false }
        return hasAlpha.map { ($0 && (properties[kCGImagePropertyHasAlpha] as? Bool) == true) || !$0 } ?? true
    }

    @Test func optionsAreRead() {
        let configuration = FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo:wardrobe=full"])
        #expect(configuration == FixtureConfiguration(set: .demo, wardrobe: .full))
        #expect(FixtureConfiguration(launchArguments: []).wardrobe == .demo)
        #expect(FixtureConfiguration(launchArguments: ["App", "-fixtures", "demo:wardrobe=nope"]).wardrobe == .demo)
    }

    /// Every demo piece but the two added by words alone, so Closet and the bundles still show
    /// a piece with no photo.
    @Test func everyDemoPieceButTwoHasARealPhotoAndCutout() async throws {
        let services = services(FixtureConfiguration())
        let garments = try await services.closet.garments()
        #expect(garments.count == 21)
        let brick = try #require(garments.first { $0.id == "g-brick-top" })
        #expect(brick.isInCloset, "A piece with no photo she can see in Closet")
        for garment in garments {
            if garment.id == "g-gray-leggings" || garment.id == "g-brick-top" {
                #expect(garment.photo == .noPhoto && garment.cutout == nil)
                continue
            }
            let cutout = try #require(garment.cutout, "\(garment.id)")
            let photoData = try await services.images.imageData(for: garment.photo, maxPixelSize: 300)
            let cutoutData = try await services.images.imageData(for: cutout.image, maxPixelSize: 300)
            #expect(isImage(photoData), "\(garment.id) photo")
            #expect(isImage(cutoutData, hasAlpha: true), "\(garment.id) cutout")
        }
    }

    /// The signals decide, as they would from Vision: lace falls back to its photo in a tile.
    @Test func mostPiecesAreStickersAndLaceIsATile() async throws {
        let garments = try await services(FixtureConfiguration()).closet.garments()
        let byID = Dictionary(uniqueKeysWithValues: garments.map { ($0.id, $0) })
        #expect(GarmentArtChoice(try #require(byID["g-navy-trousers"])).isCutOut)
        #expect(!GarmentArtChoice(try #require(byID["g-lace-top"])).isCutOut)
        let stickers = garments.filter { GarmentArtChoice($0) != .drawing && GarmentArtChoice($0).isCutOut }
        #expect(stickers.count >= 15)
    }

    @Test func theFullWardrobeAddsThirtyPiecesOfEveryKind() async throws {
        let full = try await services(FixtureConfiguration(wardrobe: .full)).closet.garments()
        #expect(full.count == 51)
        let demoIDs = Set(FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar).garments.map(\.id))
        let extras = full.filter { !demoIDs.contains($0.id) }
        #expect(extras.count == 30)
        #expect(Set(extras.map(\.category)) == Set(GarmentCategory.allCases))
        #expect(Set(full.map(\.id)).count == 51)
        #expect(full.allSatisfy { ["g-gray-leggings", "g-brick-top"].contains($0.id) || $0.cutout != nil })
        // Only the demo set takes it.
        let large = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar)
        #expect(
            large.applying(wardrobe: .full, to: .large, now: TestTime.now, calendar: TestTime.calendar).garments.count
                == large.garments.count)
    }

    @Test func everyPreviewHasItsLookAndPicture() async throws {
        let demo = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        let full = demo.applying(wardrobe: .full, to: .demo, now: TestTime.now, calendar: TestTime.calendar)
        #expect(demo.pictures.filter { if case .generated = $0.image { true } else { false } }.count == 4)
        #expect(full.pictures.filter { if case .generated = $0.image { true } else { false } }.count == 5)
        let garmentIDs = Set(full.garments.map(\.id))
        for picture in full.pictures {
            let look = try #require(full.looks.first { $0.id == picture.lookID })
            #expect(look.isSaved)
            #expect(
                look.pieces.allSatisfy {
                    if case .garment(let id) = $0.content { garmentIDs.contains(id) } else { false }
                })
            if case .generated(let photo) = picture.image {
                let data = try await SampleWardrobeProvider().imageData(for: photo, maxPixelSize: 400)
                #expect(isImage(data))
            }
        }
    }

    @Test func herExamplePhotoIsThere() async throws {
        let data = try await SampleWardrobeProvider().imageData(for: SampleWardrobe.person, maxPixelSize: 400)
        #expect(isImage(data))
        #expect(
            try await SampleWardrobeProvider().imageData(for: .sample("wardrobe:photo:../x"), maxPixelSize: 10) == nil)
    }

    @Test func tryItOnShowsThePreviewOfAMatchingLook() async throws {
        let demo = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)
        let casual = try #require(demo.looks.first { $0.id == "o-casual-jeans" })
        let picture = try await SimulatedTryOn().makePicture(of: casual, at: TestTime.now)
        #expect(picture.image == .generated(SampleWardrobe.preview("casual")))
        // Any other look keeps the drawing, and so does a look with a piece idea.
        let interview = try #require(demo.looks.first { $0.id == "o-interview" })
        #expect(try await SimulatedTryOn().makePicture(of: interview, at: TestTime.now).image == .simulated)
        let idea = try #require(demo.looks.first { $0.id == "o-brunch-idea" })
        #expect(try await SimulatedTryOn().makePicture(of: idea, at: TestTime.now).image == .simulated)
        #expect(
            try await SimulatedTryOn(usesSamplePreviews: false).makePicture(of: casual, at: TestTime.now).image
                == .simulated)
        // A preview shows the person in her try-on photo, so with no photo the picture is drawn.
        #expect(
            try await SimulatedTryOn(hasTryOnPhoto: { false }).makePicture(of: casual, at: TestTime.now).image
                == .simulated)
    }

    /// The app's Try it on follows her profile: removing the try-on photo turns previews off.
    @Test func tryItOnFollowsHerTryOnPhoto() async throws {
        let services = services(FixtureConfiguration())
        let casual = try await services.looks.look("o-casual-jeans")
        #expect(try await services.tryOn.makePicture(of: casual, at: TestTime.now).image != .simulated)
        try await services.profile.update { $0.tryOnPhoto = nil }
        #expect(try await services.tryOn.makePicture(of: casual, at: TestTime.now).image == .simulated)
    }

    /// Each cutout knows its shape, which sizes shoes in a look bundle.
    @Test func everyCutoutKnowsItsShape() throws {
        for asset in SampleWardrobe.assets {
            let cutout = try #require(SampleWardrobe.garmentCutout(asset))
            let aspect = try #require(cutout.aspectRatio, "\(asset)")
            #expect((0.3...3).contains(aspect), "\(asset): \(aspect)")
        }
        // Knee boots stand tall; heels lie wide.
        #expect(try #require(SampleWardrobe.garmentCutout("x-knee-boots")?.aspectRatio) < 0.8)
        #expect(try #require(SampleWardrobe.garmentCutout("g-black-heels")?.aspectRatio) > 1.2)
    }

    @Test func theLargeClosetUsesRealPhotosByCategoryAndTheSameEveryTime() async throws {
        let first = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar).garments
        let second = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar).garments
        #expect(first == second)
        let withPhoto = first.filter { $0.photo != .noPhoto }
        #expect(withPhoto.count > 2_000)
        #expect(withPhoto.allSatisfy { $0.cutout != nil })
        // A piece takes a photo of its own kind.
        let pool = Dictionary(uniqueKeysWithValues: SampleWardrobe.pool.map { ($0.asset, $0.category) })
        for garment in withPhoto.prefix(300) {
            guard case .sample(let name) = garment.photo, let asset = name.split(separator: ":").last else {
                Issue.record("unexpected photo \(garment.photo)")
                continue
            }
            #expect(pool[String(asset)] == garment.category)
        }
        #expect(Set(withPhoto.map(\.photo)).count > 30)
    }

    /// A piece with a photo takes the photo's colours and is named for them, so colour search and
    /// filters find what she sees (real-photo audit: "green" found a white lace top).
    @Test func theLargeClosetsColoursMatchItsPhotos() {
        let garments = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar).garments
        let pool = Dictionary(uniqueKeysWithValues: SampleWardrobe.pool.map { ($0.asset, $0) })
        var checked = 0
        for garment in garments {
            guard case .sample(let name) = garment.photo, let asset = name.split(separator: ":").last,
                let entry = pool[String(asset)]
            else { continue }
            #expect(garment.colors == entry.colors, "\(garment.name)")
            #expect(garment.name.contains(entry.colors[0].rawValue), "\(garment.name)")
            checked += 1
        }
        #expect(checked > 2_000)
    }
}
