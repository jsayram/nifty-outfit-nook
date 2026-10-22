import CoreGraphics
import Foundation
import Models

/// The plain studio backdrop that replaces her room (Jose, 19 October 2026): a soft vertical
/// gradient, light warm grey at the top to a little darker at the floor, like a photo studio's
/// paper sweep. It isn't the head's flat grey, so the two can't be confused.
public enum StudioBackdrop {
    static let top: (Double, Double, Double) = (238, 235, 230)
    static let bottom: (Double, Double, Double) = (212, 207, 200)

    /// The backdrop's colour on row `y` of a picture `height` tall.
    @inline(__always) static func color(y: Int, height: Int) -> (Double, Double, Double) {
        let t = height > 1 ? Double(y) / Double(height - 1) : 0
        return (top.0 + (bottom.0 - top.0) * t, top.1 + (bottom.1 - top.1) * t, top.2 + (bottom.2 - top.2) * t)
    }
}

/// The flat neutral grey that covers her head before anything is sent.
public enum HeadGrey {
    public static let value: UInt8 = 128

    /// True for a pixel that is still the head's grey: within a small distance of it, with no
    /// colour. The model may soften the grey slightly; it stays this close in practice.
    @inline(__always) static func matches(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Bool {
        let tolerance = 18
        let r = Int(red)
        let g = Int(green)
        let b = Int(blue)
        let grey = Int(value)
        guard abs(r - grey) <= tolerance, abs(g - grey) <= tolerance, abs(b - grey) <= tolerance else { return false }
        return max(r, g, b) - min(r, g, b) <= 10
    }
}

/// Her photo made safe to send, before the last check (that no face can be found in `faceless`).
public struct MaskedPortrait: Sendable {
    /// Her on the studio backdrop with her real head. Stays on the phone.
    public var studio: TryOnBitmap
    /// The same with her head and hair filled with flat grey. The only photo of her that is sent.
    public var faceless: TryOnBitmap
    /// Her outline.
    public var matte: TryOnMask
    /// The grey head shape.
    public var head: TryOnMask
    public var face: DetectedFace
    public var pose: BodyPose?
}

/// Builds the faceless photo (Phase 33a) and refuses whenever it can't be sure: one person, one
/// face, a clear outline, and the grey covering the whole face. Pure pixel work, so it is tested
/// on drawn pictures on the simulator; the analysis comes from `PersonAnalyzing`.
public enum HeadMasking {
    /// The thresholds, named so tests and the device checklist can refer to them.
    public enum Limits {
        /// Her outline covers at least this share of the photo.
        public static let minimumPersonShare = 0.04
        /// At most this share of her outline may be unsure (between clearly in and clearly out).
        public static let maximumUnsureShare = 0.30
        /// A face counts from this confidence. Two such faces mean two people.
        public static let faceConfidence: Float = 0.3
        /// A second outline at least this share of the photo is a second person.
        public static let secondPersonShare = 0.015
        /// The face must be at least this many pixels wide to check it properly.
        public static let minimumFaceWidth = 24.0
    }

    public static func mask(_ image: TryOnBitmap, analysis: PersonAnalysis) throws(TryOnPrepareProblem) -> MaskedPortrait {
        let width = image.width
        let height = image.height
        let matte = analysis.matte.resized(width: width, height: height)

        // One person, one face, a clear outline.
        let faces = analysis.faces.filter { $0.confidence >= Limits.faceConfidence }
        let personPixels = matte.count(atLeast: 128)
        guard Double(personPixels) >= Limits.minimumPersonShare * Double(width * height) else { throw .noPerson }
        guard !faces.isEmpty else { throw .noFace }
        guard faces.count == 1, outlines(in: matte) <= 1 else { throw .severalPeople }
        let unsure = matte.values.count { $0 > 32 && $0 < 224 }
        let touched = matte.count(atLeast: 33)
        guard touched > 0, Double(unsure) / Double(touched) <= Limits.maximumUnsureShare else {
            throw .unclearOutline
        }
        let face = faces[0]
        let box = face.box.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !box.isNull, box.width >= Limits.minimumFaceWidth, coverage(of: box, by: matte) >= 0.5 else {
            throw .unclearOutline
        }

        let head = headShape(face: face, box: box, matte: matte)
        // The grey must cover every pixel of the face's box.
        guard coverage(of: box, by: head) >= 0.999 else { throw .faceStillVisible }

        var studio = image
        var faceless = image
        for y in 0..<height {
            let backdrop = StudioBackdrop.color(y: y, height: height)
            for x in 0..<width {
                let a = Double(matte[x, y]) / 255
                let (r, g, b) = image.rgb(x, y)
                let red = UInt8((Double(r) * a + backdrop.0 * (1 - a)).rounded())
                let green = UInt8((Double(g) * a + backdrop.1 * (1 - a)).rounded())
                let blue = UInt8((Double(b) * a + backdrop.2 * (1 - a)).rounded())
                studio.set(x, y, red, green, blue)
                if head[x, y] >= 128 {
                    faceless.set(x, y, HeadGrey.value, HeadGrey.value, HeadGrey.value)
                } else {
                    faceless.set(x, y, red, green, blue)
                }
            }
        }
        return MaskedPortrait(
            studio: studio, faceless: faceless, matte: matte, head: head, face: face, pose: analysis.pose)
    }

    /// Her outline above the chin, near the face, joined with a padded oval around the face: a
    /// head shape that takes in her hair, not a plain oval.
    static func headShape(face: DetectedFace, box: CGRect, matte: TryOnMask) -> TryOnMask {
        let width = matte.width
        let height = matte.height
        let faceWidth = box.width
        let faceHeight = box.height
        let chin = max(face.chinY ?? box.maxY, box.maxY)
        let chinLine = min(Double(height - 1), chin + 0.08 * faceHeight)
        let left = max(0, Int(box.minX - 1.2 * faceWidth))
        let right = min(width - 1, Int(box.maxX + 1.2 * faceWidth))
        let centerX = box.midX
        let centerY = box.midY - 0.05 * faceHeight
        let radiusX = 0.68 * faceWidth
        let radiusY = 0.75 * faceHeight
        var head = TryOnMask(width: width, height: height)
        let lastRow = Int(chinLine)
        guard lastRow >= 0 else { return head }
        for y in 0...lastRow {
            let dy = (Double(y) + 0.5 - centerY) / radiusY
            for x in 0..<width {
                let inBand = x >= left && x <= right && matte[x, y] >= 64
                let dx = (Double(x) + 0.5 - centerX) / radiusX
                if inBand || dx * dx + dy * dy <= 1 { head[x, y] = 255 }
            }
        }
        // A small margin, so wisps at the outline's edge are covered too.
        let margin = max(2, Int((0.04 * faceWidth).rounded()))
        var grown = head.dilated(by: margin)
        // The margin never reaches below the chin line, where her neck and collar are.
        for y in min(height, lastRow + 1)..<height {
            for x in 0..<width { grown[x, y] = 0 }
        }
        // ...but the face box itself is always covered, whatever the outline says.
        for y in Int(box.minY)..<min(height, Int(box.maxY.rounded(.up))) {
            for x in Int(box.minX)..<min(width, Int(box.maxX.rounded(.up))) { grown[x, y] = 255 }
        }
        return grown
    }

    /// The share of `box`'s pixels that are at least 128 in `mask`.
    static func coverage(of box: CGRect, by mask: TryOnMask) -> Double {
        let minX = max(0, Int(box.minX))
        let maxX = min(mask.width, Int(box.maxX.rounded(.up)))
        let minY = max(0, Int(box.minY))
        let maxY = min(mask.height, Int(box.maxY.rounded(.up)))
        guard maxX > minX, maxY > minY else { return 0 }
        var covered = 0
        for y in minY..<maxY {
            for x in minX..<maxX where mask[x, y] >= 128 { covered += 1 }
        }
        return Double(covered) / Double((maxX - minX) * (maxY - minY))
    }

    /// How many separate outlines of a real size the matte holds, counted on a coarse grid.
    static func outlines(in matte: TryOnMask) -> Int {
        let step = max(1, min(matte.width, matte.height) / 160)
        let width = matte.width / step
        let height = matte.height / step
        guard width > 0, height > 0 else { return 0 }
        var grid = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width { grid[y * width + x] = matte[x * step, y * step] >= 128 }
        }
        var seen = [Bool](repeating: false, count: grid.count)
        let minimum = Int(HeadMasking.Limits.secondPersonShare * Double(width * height))
        var count = 0
        for start in grid.indices where grid[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var size = 0
            while let index = stack.popLast() {
                size += 1
                let x = index % width
                let y = index / width
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let next = ny * width + nx
                    if grid[next] && !seen[next] {
                        seen[next] = true
                        stack.append(next)
                    }
                }
            }
            if size >= max(1, minimum) { count += 1 }
        }
        return count
    }
}

/// Puts her real head back on the dressed picture (Phase 33a), on the phone, with no extra call.
///
/// 1. If the model moved her a little, her head is moved with her neck and shoulders (body pose).
/// 2. Only where the flat grey is still there, her own outline from the original goes back, so
///    a hat, scarf or collar the model drew over the grey stays in front.
/// 3. Grey left outside her outline becomes the original backdrop, times the brightness change
///    measured on backdrop the model left alone nearby.
/// 4. The edges are feathered.
public enum HeadRestore {
    /// Moves points of the original photo to where they are in the dressed one.
    public struct Alignment: Sendable, Equatable {
        public var dx: Double
        public var dy: Double
        public var scale: Double
        /// The point the scale is about (her neck in the original).
        public var anchor: CGPoint

        public static let identity = Alignment(dx: 0, dy: 0, scale: 1, anchor: .zero)

        public var isIdentity: Bool { dx == 0 && dy == 0 && scale == 1 }

        /// Where a point of the original lands in the dressed picture.
        func apply(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: anchor.x + (point.x - anchor.x) * scale + dx, y: anchor.y + (point.y - anchor.y) * scale + dy)
        }

        /// Where a point of the dressed picture came from in the original.
        func invert(x: Double, y: Double) -> (Double, Double) {
            ((x - dx - anchor.x) / scale + anchor.x, (y - dy - anchor.y) / scale + anchor.y)
        }
    }

    /// How far the model moved her, from her neck and shoulders in both pictures. Small moves are
    /// ignored; moves too large to trust (or no pose in either picture) keep her head where it was.
    public static func alignment(from original: BodyPose?, to dressed: BodyPose?, width: Int) -> Alignment {
        guard let original, let dressed else { return .identity }
        var scale = 1.0
        if let before = original.shoulderWidth, let after = dressed.shoulderWidth, before > 1 {
            scale = min(1.08, max(0.92, after / before))
        }
        let dx = dressed.neck.x - original.neck.x
        let dy = dressed.neck.y - original.neck.y
        let limit = 0.08 * Double(width)
        guard abs(dx) <= limit, abs(dy) <= limit else { return .identity }
        if abs(dx) < 0.005 * Double(width) && abs(dy) < 0.005 * Double(width) && abs(scale - 1) < 0.01 {
            return .identity
        }
        return Alignment(dx: dx, dy: dy, scale: scale, anchor: original.neck)
    }

    /// The finished picture, the size of `studio`.
    public static func restore(
        dressed input: TryOnBitmap, studio: TryOnBitmap, matte: TryOnMask, head: TryOnMask, faceWidth: Double,
        alignment: Alignment
    ) -> TryOnBitmap? {
        let width = studio.width
        let height = studio.height
        guard let dressed = input.fitted(width: width, height: height) else { return nil }
        let movedStudio = alignment.isIdentity ? studio : warp(studio, alignment)
        let movedMatte = alignment.isIdentity ? matte : warp(matte, alignment)
        let movedHead = alignment.isIdentity ? head : warp(head, alignment)
        let face = faceWidth * alignment.scale

        // Where to look for grey: the head shape and a margin around it.
        let search = movedHead.dilated(by: max(3, Int(0.15 * face)))
        var grey = TryOnMask(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where search[x, y] >= 128 {
                let (r, g, b) = dressed.rgb(x, y)
                if HeadGrey.matches(r, g, b) { grey[x, y] = 255 }
            }
        }

        // The brightness change on backdrop the model kept: a ring around the search area, outside
        // her outline and not grey.
        let ring = search.dilated(by: max(4, Int(0.3 * face)))
        var ratios: ([Double], [Double], [Double]) = ([], [], [])
        for y in 0..<height {
            let backdrop = StudioBackdrop.color(y: y, height: height)
            for x in 0..<width where ring[x, y] >= 128 && search[x, y] < 128 && movedMatte[x, y] < 8 {
                let (r, g, b) = dressed.rgb(x, y)
                guard !HeadGrey.matches(r, g, b) else { continue }
                ratios.0.append(Double(r) / backdrop.0)
                ratios.1.append(Double(g) / backdrop.1)
                ratios.2.append(Double(b) / backdrop.2)
            }
        }
        let gain = ratios.0.count >= 50 ? (median(ratios.0), median(ratios.1), median(ratios.2)) : (1.0, 1.0, 1.0)

        // Feathered: grey pixels are replaced fully, a two-pixel edge around them blends.
        let edge = grey.dilated(by: 2).intersected(with: search).blurred(by: 2)
        var output = dressed
        for y in 0..<height {
            let backdrop = StudioBackdrop.color(y: y, height: height)
            let lit = (backdrop.0 * gain.0, backdrop.1 * gain.1, backdrop.2 * gain.2)
            for x in 0..<width {
                let weight = grey[x, y] >= 128 ? 1.0 : Double(edge[x, y]) / 255
                guard weight > 0 else { continue }
                // Her original pixel (her outline over the backdrop, as it was), with the backdrop
                // part brightened like the rest of the backdrop.
                let a = Double(movedMatte[x, y]) / 255
                let (sr, sg, sb) = movedStudio.rgb(x, y)
                let red = Double(sr) + (1 - a) * backdrop.0 * (gain.0 - 1)
                let green = Double(sg) + (1 - a) * backdrop.1 * (gain.1 - 1)
                let blue = Double(sb) + (1 - a) * backdrop.2 * (gain.2 - 1)
                let replacement = a > 0 ? (red, green, blue) : lit
                let (dr, dg, db) = dressed.rgb(x, y)
                output.set(
                    x, y, clamp(Double(dr) * (1 - weight) + replacement.0 * weight),
                    clamp(Double(dg) * (1 - weight) + replacement.1 * weight),
                    clamp(Double(db) * (1 - weight) + replacement.2 * weight))
            }
        }
        return output
    }

    /// Grey pixels left in the head's area, for tests and the device checklist.
    public static func greyLeft(in picture: TryOnBitmap, head: TryOnMask, margin: Int) -> Int {
        let search = head.dilated(by: margin)
        var count = 0
        for y in 0..<picture.height {
            for x in 0..<picture.width where search[x, y] >= 128 {
                let (r, g, b) = picture.rgb(x, y)
                if HeadGrey.matches(r, g, b) { count += 1 }
            }
        }
        return count
    }

    static func warp(_ bitmap: TryOnBitmap, _ alignment: Alignment) -> TryOnBitmap {
        var output = bitmap
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let (sx, sy) = alignment.invert(x: Double(x), y: Double(y))
                let ix = min(bitmap.width - 1, max(0, Int(sx.rounded())))
                let iy = min(bitmap.height - 1, max(0, Int(sy.rounded())))
                let (r, g, b) = bitmap.rgb(ix, iy)
                output.set(x, y, r, g, b)
            }
        }
        return output
    }

    static func warp(_ mask: TryOnMask, _ alignment: Alignment) -> TryOnMask {
        var output = TryOnMask(width: mask.width, height: mask.height)
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                let (sx, sy) = alignment.invert(x: Double(x), y: Double(y))
                let ix = Int(sx.rounded())
                let iy = Int(sy.rounded())
                guard ix >= 0, iy >= 0, ix < mask.width, iy < mask.height else { continue }
                output[x, y] = mask[ix, iy]
            }
        }
        return output
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return min(1.25, max(0.8, sorted[sorted.count / 2]))
    }

    @inline(__always) private static func clamp(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, value.rounded())))
    }
}
