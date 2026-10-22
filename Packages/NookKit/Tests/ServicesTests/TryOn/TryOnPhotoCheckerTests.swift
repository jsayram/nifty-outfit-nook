import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Services

/// 33b: the check before a photo becomes her try-on photo. It runs the same fail-closed checks
/// try-on runs (`PhoneTryOn.facelessPortrait`), so these use the same drawn stand-in people (never
/// a photo of anyone) and the same stand-in analyzers as `PhoneTryOnTests`.
struct TryOnPhotoCheckerTests {
    let folder: URL
    let files: PhotoFileStore

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "tryon-check-\(UUID().uuidString)")
        files = PhotoFileStore(directory: folder, freeSpace: { 10_000_000_000 })
    }

    func checker(
        _ analyzer: any PersonAnalyzing = SyntheticPersonAnalyzer(), frames: (any FrameAnalyzing)? = nil
    ) -> TryOnPhotoChecker {
        TryOnPhotoChecker(analyzer: analyzer, frames: frames, files: files, images: DrawnGarments())
    }

    func photo(_ drawing: TryOnBitmap = SyntheticPerson.draw().bitmap) throws -> PhotoReference {
        let png = try #require(drawing.png())
        return .stored(EntityID(try files.add(png)))
    }

    // MARK: A photo that works

    @Test func aClearPhotoOfJustHerIsFineAndNothingIsWritten() async throws {
        let photo = try photo()
        let before = files.ids()
        #expect(await checker().check(photo) == .fine(tips: []))
        // The faceless picture the check makes is thrown away: no file, nothing sent.
        #expect(files.ids() == before)
    }

    // MARK: Fail closed, before she saves

    @Test func twoPeopleNoFaceOrNoPhotoAreExplained() async throws {
        let checker = checker()
        #expect(
            await checker.check(try photo(SyntheticPerson.draw(centers: [0.3, 0.72]).bitmap))
                == .problem(.severalPeople))
        #expect(await checker.check(try photo(SyntheticPerson.draw(facingAway: true).bitmap)) == .problem(.noFace))
        #expect(await checker.check(.noPhoto) == .problem(.noTryOnPhoto))
    }

    @Test func aPhotoThatCantBeReadIsExplained() async throws {
        let id = try files.add(Data("not a picture".utf8))
        #expect(await checker().check(.stored(EntityID(id))) == .problem(.photoUnreadable))
        #expect(await checker().check(.stored(EntityID("gone"))) == .problem(.photoUnreadable))
    }

    @Test func aFaceThatCouldStillBeFoundAfterMaskingIsRefused() async throws {
        let photo = try photo()
        #expect(await checker(SeesAFaceAfterMasking()).check(photo) == .problem(.faceStillVisible))
    }

    @Test func checksThatCannotRunSayTheyCouldNot() async throws {
        #expect(await checker(BrokenAnalyzer()).check(try photo()) == .problem(.checksUnavailable))
    }

    /// The point of checking at setup: a photo she's told is fine is one try-on accepts, and one
    /// she's told won't work is one try-on refuses for the same reason.
    @Test func theCheckAndTryOnAgreeOnEveryPhoto() async throws {
        let paid = RecordingPaid()
        let pieces = [PhoneTryOnTests.pieces[0]]
        let cases: [(TryOnBitmap, any PersonAnalyzing)] = [
            (SyntheticPerson.draw().bitmap, SyntheticPersonAnalyzer()),
            (SyntheticPerson.draw(centers: [0.3, 0.72]).bitmap, SyntheticPersonAnalyzer()),
            (SyntheticPerson.draw(facingAway: true).bitmap, SyntheticPersonAnalyzer()),
            (SyntheticPerson.draw().bitmap, SeesAFaceAfterMasking()),
            (SyntheticPerson.draw().bitmap, BrokenAnalyzer()),
        ]
        for (drawing, analyzer) in cases {
            let photo = try photo(drawing)
            let tryOn = PhoneTryOn(analyzer: analyzer, paid: paid, files: files, images: DrawnGarments())
            let verdict = await checker(analyzer).check(photo)
            do {
                _ = try await tryOn.prepare(photo: photo, pieces: pieces)
                #expect(verdict == .fine(tips: []))
            } catch {
                #expect(verdict == .problem(error))
            }
        }
        #expect(paid.calls.isEmpty)
    }

    // MARK: Gentle tips

    /// What a frame shows: one person facing the camera in the middle. `armsClose` puts her wrists
    /// against her body, `cutOff` runs her past the top and bottom of the picture, `dark` dims it.
    static func seen(armsClose: Bool = false, cutOff: Bool = false, dark: Bool = false) -> FramingObservation {
        typealias Point = FramingObservation.Point
        let reach = armsClose ? 0.09 : 0.22
        let joints: [FramingObservation.Joint: Point] = [
            .nose: Point(x: 0.5, y: 0.12), .leftEye: Point(x: 0.48, y: 0.11), .rightEye: Point(x: 0.52, y: 0.11),
            .neck: Point(x: 0.5, y: 0.2), .leftShoulder: Point(x: 0.4, y: 0.22), .rightShoulder: Point(x: 0.6, y: 0.22),
            .leftWrist: Point(x: 0.5 - reach, y: 0.58), .rightWrist: Point(x: 0.5 + reach, y: 0.58),
            .leftHip: Point(x: 0.44, y: 0.54), .rightHip: Point(x: 0.56, y: 0.54),
            .leftAnkle: Point(x: 0.44, y: 0.92), .rightAnkle: Point(x: 0.56, y: 0.92),
        ]
        return FramingObservation(
            people: 1, joints: joints,
            outline: cutOff
                ? CGRect(x: 0.3, y: 0.0, width: 0.4, height: 1.0) : CGRect(x: 0.3, y: 0.08, width: 0.4, height: 0.86),
            frameBrightness: dark ? 0.1 : 0.55, subjectBrightness: dark ? 0.1 : 0.55)
    }

    @Test func tipsComeFromTheFramingRulesAndOnlyForWhatThePhotoShows() async throws {
        let tips = try await checker(frames: FixedFrames(Self.seen(armsClose: true, cutOff: true, dark: true)))
            .check(photo())
        // Step back, arms and light, in that order.
        #expect(tips == .fine(tips: [.stepBack, .armsOut, .moreLight]))
        // Standing off to one side isn't a tip: she isn't framing this photo now.
        var aside = Self.seen()
        aside.outline = CGRect(x: 0.6, y: 0.08, width: 0.3, height: 0.86)
        #expect(try await checker(frames: FixedFrames(aside)).check(photo()) == .fine(tips: []))
    }

    @Test func noTipsWhenThePhotoCantBeLookedAtOrLooksGood() async throws {
        #expect(try await checker(frames: FixedFrames(nil)).check(photo()) == .fine(tips: []))
        #expect(try await checker(frames: FixedFrames(Self.seen())).check(photo()) == .fine(tips: []))
    }

    @Test func aProblemIsNeverSoftenedIntoATip() async throws {
        let result = try await checker(SeesAFaceAfterMasking(), frames: FixedFrames(Self.seen())).check(photo())
        #expect(result == .problem(.faceStillVisible))
    }
}

/// Always sees the same thing.
struct FixedFrames: FrameAnalyzing {
    let seen: FramingObservation?

    init(_ seen: FramingObservation?) { self.seen = seen }

    func observe(_ frame: AnalysisFrame) async -> FramingObservation? { seen }
}
