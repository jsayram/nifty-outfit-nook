import CoreGraphics
import Foundation
import ImageIO
import Models
import Testing

@testable import Fixtures

struct CutoutFixtureTests {
    @Test func theStandInHandsThePhotoBackWithItsSignals() async throws {
        let photo = SyntheticGarmentPhotos.jpeg(.flatLayTee, width: 600, height: 750)
        let result = try await StandInCutoutService().cutout(from: photo)
        #expect(result.imageData == photo)
        #expect(result.pixelWidth == 600 && result.pixelHeight == 750)
        #expect(result.quality == StandInCutoutService.cleanQuality)
        #expect(CutoutThresholds.proposed.suggestsSticker(result.quality))
    }

    @Test func theStandInCanReturnAnyQuality() async throws {
        let messy = CutoutQuality(
            instanceCount: 3, coverage: 0.95, largestInstanceShare: 0.4, touchedEdges: [.left, .right],
            softEdgeRatio: 0.5, subjectBounds: .whole)
        let result = try await StandInCutoutService(outcome: .lifted(messy)).cutout(
            from: SyntheticGarmentPhotos.jpeg(.emptyBed, width: 100, height: 100))
        #expect(result.quality == messy)
        #expect(!CutoutThresholds.proposed.suggestsSticker(result.quality))
    }

    @Test(arguments: [CutoutError.noSubject, .unsupported, .failed])
    func theStandInFailsWhenTold(error: CutoutError) async {
        await #expect(throws: error) {
            try await StandInCutoutService(outcome: .fails(error)).cutout(from: Data())
        }
    }

    @Test func theStandInRefusesWhatIsNotAPicture() async {
        await #expect(throws: CutoutError.unreadableImage) {
            try await StandInCutoutService().cutout(from: Data("nope".utf8))
        }
    }

    @Test func theStandInStopsWhenCancelledWhileWaiting() async {
        let task = Task { () async throws(CutoutError) -> CutoutResult in
            try await StandInCutoutService(latency: .seconds(10)).cutout(from: Data())
        }
        task.cancel()
        await #expect(throws: CutoutError.cancelled) { try await task.value }
    }

    @Test func fixtureServicesHaveTheStandIn() async throws {
        let services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        let result = try await services.cutouts.cutout(from: SyntheticGarmentPhotos.jpeg(.flatLayTee))
        #expect(result.quality == StandInCutoutService.cleanQuality)
    }

    // MARK: Synthetic photos

    @Test(arguments: SyntheticGarmentPhotos.Scene.allCases)
    func everySceneIsAReadableJPEGOfTheAskedSize(scene: SyntheticGarmentPhotos.Scene) throws {
        let data = SyntheticGarmentPhotos.jpeg(scene, width: 300, height: 400)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 300)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 400)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func scenesAreTheSameOnEveryRun() {
        #expect(
            SyntheticGarmentPhotos.jpeg(.stripedSweater, width: 200, height: 250)
                == SyntheticGarmentPhotos.jpeg(.stripedSweater, width: 200, height: 250))
        #expect(
            SyntheticGarmentPhotos.jpeg(.flatLayTee, width: 200, height: 250)
                != SyntheticGarmentPhotos.jpeg(.darkOnDark, width: 200, height: 250))
    }

    @Test func aPhotoCanCarryMadeUpLocation() throws {
        let data = SyntheticGarmentPhotos.jpeg(.flatLayTee, width: 200, height: 250, location: true)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] != nil)
    }
}
