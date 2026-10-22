import CoreGraphics
import Foundation
import Models
import Testing

@testable import Services

/// 33a: the faceless photo, on drawn pictures (`SyntheticPerson`, never a photo of anyone) read by
/// `SyntheticPersonAnalyzer`, since simulators can't run Apple Vision's person, face and pose
/// requests. The real Vision run is on the device checklist (docs/try-on-pictures.md).
struct HeadMaskingTests {
    static let analyzer = SyntheticPersonAnalyzer()

    static func masked(
        _ drawing: (bitmap: TryOnBitmap, figures: [SyntheticPerson.Figure]) = SyntheticPerson.draw(),
        analyzer: SyntheticPersonAnalyzer = analyzer
    ) async throws -> MaskedPortrait {
        try HeadMasking.mask(drawing.bitmap, analysis: try await analyzer.analyze(drawing.bitmap))
    }

    static func problem(
        _ drawing: (bitmap: TryOnBitmap, figures: [SyntheticPerson.Figure]),
        analyzer: SyntheticPersonAnalyzer = analyzer
    ) async throws -> TryOnPrepareProblem? {
        let analysis = try await analyzer.analyze(drawing.bitmap)
        do {
            _ = try HeadMasking.mask(drawing.bitmap, analysis: analysis)
            return nil
        } catch {
            return error
        }
    }

    @Test func theAnalyzerFindsTheDrawnFace() async throws {
        let drawing = SyntheticPerson.draw()
        let faces = try await Self.analyzer.faces(in: drawing.bitmap)
        let drawn = try #require(drawing.figures.first?.face)
        let found = try #require(faces.first?.box)
        #expect(faces.count == 1)
        #expect(abs(found.midX - drawn.midX) < 3 && abs(found.midY - drawn.midY) < 3)
    }

    @Test func noFaceCanBeFoundAfterMasking() async throws {
        let portrait = try await Self.masked()
        #expect(try await Self.analyzer.faces(in: portrait.faceless).isEmpty)
        // Every pixel of the face's box is the flat grey.
        let box = portrait.face.box
        for y in Int(box.minY)..<Int(box.maxY) {
            for x in Int(box.minX)..<Int(box.maxX) {
                let (r, g, b) = portrait.faceless.rgb(x, y)
                #expect(r == HeadGrey.value && g == HeadGrey.value && b == HeadGrey.value)
            }
        }
    }

    @Test func theGreyShapeTakesInHerHairNotJustAnOval() async throws {
        let drawing = SyntheticPerson.draw()
        let portrait = try await Self.masked(drawing)
        let face = try #require(drawing.figures.first?.face)
        // Hair sits above and beside the face in the drawing; it's grey too.
        let hairTop = CGPoint(x: face.midX, y: face.minY - face.height * 0.12)
        let (r, g, b) = portrait.faceless.rgb(Int(hairTop.x), Int(hairTop.y))
        #expect(r == HeadGrey.value && g == HeadGrey.value && b == HeadGrey.value)
        // Nothing of the hair colour is left anywhere.
        var hair = 0
        for y in 0..<portrait.faceless.height {
            for x in 0..<portrait.faceless.width
            where SyntheticPerson.distance(portrait.faceless.rgb(x, y), SyntheticPerson.Palette.hair) < 30 {
                hair += 1
            }
        }
        #expect(hair == 0)
        // Her neck and shoulders, below the chin, are left as they are.
        let neck = try #require(drawing.figures.first?.neck)
        #expect(SyntheticPerson.distance(portrait.faceless.rgb(Int(neck.x), Int(neck.y)), SyntheticPerson.Palette.skin) < 12)
    }

    @Test func theRoomIsReplacedByThePlainStudioBackdrop() async throws {
        let portrait = try await Self.masked()
        var room = 0
        for y in 0..<portrait.faceless.height {
            for x in 0..<portrait.faceless.width {
                let pixel = portrait.faceless.rgb(x, y)
                if SyntheticPerson.Palette.room.contains(where: { SyntheticPerson.distance(pixel, $0) < 12 }) {
                    room += 1
                }
            }
        }
        #expect(room == 0)
        let corner = portrait.faceless.rgb(2, 2)
        #expect(abs(Int(corner.0) - Int(StudioBackdrop.top.0)) <= 1)
        // The photo with her real head (kept on the phone) has the same backdrop.
        #expect(portrait.studio.rgb(2, 2) == corner)
    }

    // MARK: Fail closed

    @Test func twoPeopleAreRefused() async throws {
        #expect(try await Self.problem(SyntheticPerson.draw(centers: [0.3, 0.72])) == .severalPeople)
    }

    @Test func aPhotoWithNoFaceIsRefused() async throws {
        #expect(try await Self.problem(SyntheticPerson.draw(facingAway: true)) == .noFace)
    }

    @Test func aPhotoWithNoPersonIsRefused() async throws {
        #expect(try await Self.problem(SyntheticPerson.draw(centers: [])) == .noPerson)
    }

    @Test func aLowConfidenceOutlineIsRefused() async throws {
        // The outline only half sure everywhere, as a blurry or busy photo gives.
        let unsure = SyntheticPersonAnalyzer { analysis in
            var analysis = analysis
            analysis.matte.values = analysis.matte.values.map { $0 > 0 ? 128 : 0 }
            return analysis
        }
        #expect(try await Self.problem(SyntheticPerson.draw(), analyzer: unsure) == .unclearOutline)
    }

    @Test func aSecondFaceIsRefusedEvenWithOneOutline() async throws {
        let extra = SyntheticPersonAnalyzer { analysis in
            var analysis = analysis
            analysis.faces.append(DetectedFace(box: CGRect(x: 10, y: 10, width: 40, height: 50), confidence: 0.4))
            return analysis
        }
        #expect(try await Self.problem(SyntheticPerson.draw(), analyzer: extra) == .severalPeople)
    }

    @Test func aFaceOutsideHerOutlineIsRefused() async throws {
        let elsewhere = SyntheticPersonAnalyzer { analysis in
            var analysis = analysis
            analysis.faces = [DetectedFace(box: CGRect(x: 4, y: 560, width: 40, height: 50), confidence: 0.9)]
            return analysis
        }
        #expect(try await Self.problem(SyntheticPerson.draw(), analyzer: elsewhere) == .unclearOutline)
    }

    @Test func masksSurviveAPNGRoundTrip() async throws {
        let portrait = try await Self.masked()
        let data = try #require(portrait.head.png())
        #expect(TryOnMask.decode(data) == portrait.head)
    }
}
