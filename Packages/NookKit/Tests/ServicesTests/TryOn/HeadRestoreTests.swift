import CoreGraphics
import Foundation
import Models
import Testing

@testable import Services

/// 33a: putting her head back on the dressed picture, on drawn pictures. The "dressed" pictures
/// are made here the way the model returns them: the faceless photo with new clothes drawn on,
/// sometimes moved a little, sometimes with a hat over the top of the grey shape.
struct HeadRestoreTests {
    let drawing = SyntheticPerson.draw()
    let portrait: MaskedPortrait

    init() async throws {
        portrait = try HeadMasking.mask(
            drawing.bitmap, analysis: try await SyntheticPersonAnalyzer().analyze(drawing.bitmap))
    }

    /// The faceless photo with the top recoloured (a "new" top), moved by `dx`, `dy`.
    func dressed(dx: Int = 0, dy: Int = 0, hat: Bool = false, backdropGain: Double = 1) -> TryOnBitmap {
        let source = portrait.faceless
        var output = TryOnBitmap(width: source.width, height: source.height)
        for y in 0..<source.height {
            let backdrop = StudioBackdrop.color(y: y, height: source.height)
            for x in 0..<source.width {
                let sx = x - dx
                let sy = y - dy
                guard sx >= 0, sy >= 0, sx < source.width, sy < source.height else {
                    output.set(x, y, UInt8(backdrop.0), UInt8(backdrop.1), UInt8(backdrop.2))
                    continue
                }
                var (r, g, b) = source.rgb(sx, sy)
                if SyntheticPerson.distance((r, g, b), SyntheticPerson.Palette.top) < 30 { (r, g, b) = (190, 60, 70) }
                if portrait.matte[sx, sy] == 0, backdropGain != 1 {
                    r = UInt8(min(255, Double(r) * backdropGain))
                    g = UInt8(min(255, Double(g) * backdropGain))
                    b = UInt8(min(255, Double(b) * backdropGain))
                }
                output.set(x, y, r, g, b)
            }
        }
        if hat {
            // A beanie pulled down over the top of the grey shape.
            let face = portrait.face.box.offsetBy(dx: Double(dx), dy: Double(dy))
            for y in Int(face.minY - face.height * 0.35)..<Int(face.minY + face.height * 0.2) {
                for x in Int(face.minX - face.width * 0.15)..<Int(face.maxX + face.width * 0.15) {
                    output.set(x, y, 40, 140, 60)
                }
            }
        }
        return output
    }

    func restore(_ picture: TryOnBitmap, alignment: HeadRestore.Alignment = .identity) throws -> TryOnBitmap {
        try #require(
            HeadRestore.restore(
                dressed: picture, studio: portrait.studio, matte: portrait.matte, head: portrait.head,
                faceWidth: portrait.face.box.width, alignment: alignment))
    }

    @Test func noGreyIsLeftAndHerFaceIsBack() async throws {
        let restored = try restore(dressed())
        #expect(HeadRestore.greyLeft(in: restored, head: portrait.head, margin: 12) == 0)
        let faces = try await SyntheticPersonAnalyzer().faces(in: restored)
        #expect(faces.count == 1)
        #expect(abs((faces.first?.box.midX ?? 0) - portrait.face.box.midX) < 2)
        // The new top the model drew stays.
        let chest = try #require(drawing.figures.first?.neck)
        #expect(restored.rgb(Int(chest.x), Int(chest.y) + 40) == (190, 60, 70))
    }

    @Test func herHeadFollowsHerNeckWhenTheModelMovedHer() async throws {
        let picture = dressed(dx: 12, dy: 8)
        let figure = try #require(drawing.figures.first)
        let before = BodyPose(neck: figure.neck, leftShoulder: figure.leftShoulder, rightShoulder: figure.rightShoulder)
        let after = BodyPose(
            neck: figure.neck.applying(.init(translationX: 12, y: 8)),
            leftShoulder: figure.leftShoulder.applying(.init(translationX: 12, y: 8)),
            rightShoulder: figure.rightShoulder.applying(.init(translationX: 12, y: 8)))
        let alignment = HeadRestore.alignment(from: before, to: after, width: picture.width)
        #expect(alignment.dx == 12 && alignment.dy == 8 && alignment.scale == 1)
        let restored = try restore(picture, alignment: alignment)
        let movedHead = HeadRestore.warp(portrait.head, alignment)
        #expect(HeadRestore.greyLeft(in: restored, head: movedHead, margin: 12) == 0)
        let faces = try await SyntheticPersonAnalyzer().faces(in: restored)
        let face = try #require(faces.first)
        #expect(abs(face.box.midX - (portrait.face.box.midX + 12)) < 2.5)
        #expect(abs(face.box.midY - (portrait.face.box.midY + 8)) < 2.5)
    }

    @Test func aHatTheModelDrewStaysInFront() async throws {
        let restored = try restore(dressed(hat: true))
        #expect(HeadRestore.greyLeft(in: restored, head: portrait.head, margin: 12) == 0)
        let face = portrait.face.box
        // The hat's middle is still the hat.
        #expect(restored.rgb(Int(face.midX), Int(face.minY)) == (40, 140, 60))
        // Her eyes below it are back.
        #expect(try await SyntheticPersonAnalyzer().faces(in: restored).count == 1)
    }

    @Test func greyOutsideHerOutlineBecomesTheBackdropAsTheModelLitIt() throws {
        let restored = try restore(dressed(backdropGain: 1.05))
        // A pixel in the grey shape that was backdrop in the original (outside her outline).
        var checked = 0
        for y in 0..<restored.height {
            for x in 0..<restored.width where portrait.head[x, y] >= 128 && portrait.matte[x, y] == 0 {
                let backdrop = StudioBackdrop.color(y: y, height: restored.height)
                let (r, _, _) = restored.rgb(x, y)
                #expect(abs(Double(r) - min(255, backdrop.0 * 1.05)) <= 3)
                checked += 1
                if checked > 50 { return }
            }
        }
        #expect(checked > 0)
    }

    @Test func largeOrMissingMovesKeepHerHeadWhereItWas() {
        let neck = CGPoint(x: 200, y: 200)
        #expect(HeadRestore.alignment(from: nil, to: BodyPose(neck: neck), width: 480) == .identity)
        #expect(
            HeadRestore.alignment(
                from: BodyPose(neck: neck), to: BodyPose(neck: CGPoint(x: 300, y: 200)), width: 480) == .identity)
        #expect(
            HeadRestore.alignment(from: BodyPose(neck: neck), to: BodyPose(neck: CGPoint(x: 201, y: 200)), width: 480)
                == .identity)
    }
}
