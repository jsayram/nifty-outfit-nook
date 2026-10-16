import CoreGraphics
import Foundation
import Models

/// Pieces with drawn sample photos and stand-in cutouts (Phase 8b), so the sticker look and the
/// photo tile fallback can be seen in the app without real photos: `-fixtures demo:photos=samples`.
///
/// The photos are `SyntheticGarmentPhotos` scenes. The simulator can't lift subjects, so each
/// cutout is the same scene drawn without its background, with quality signals worked out from
/// that drawing and the signals the Mac's Vision gave for the scene (`docs/cutout-feasibility.md`).
/// Six come out clean enough for a sticker; the white tee (fuzzy edges) and the tee with shoes
/// (two things in one photo) fall back to the photo tile.
public enum SamplePhotoGarments {
    /// One sample piece: its scene and the signals that aren't read from the drawing.
    struct Sample {
        let scene: SyntheticGarmentPhotos.Scene
        let name: String
        let category: GarmentCategory
        let colors: [ColorName]
        let instanceCount: Int
        let largestInstanceShare: Double
        let softEdgeRatio: Double
    }

    static let samples: [Sample] = [
        Sample(
            scene: .flatLayTee, name: "Navy tee", category: .top, colors: [.navy], instanceCount: 1,
            largestInstanceShare: 1, softEdgeRatio: 0.05),
        Sample(
            scene: .stripedSweater, name: "Striped sweater", category: .top, colors: [.red, .cream],
            instanceCount: 1, largestInstanceShare: 1, softEdgeRatio: 0.06),
        Sample(
            scene: .hangerDress, name: "Wine dress", category: .dress, colors: [.burgundy], instanceCount: 2,
            largestInstanceShare: 0.9, softEdgeRatio: 0.05),
        Sample(
            scene: .shinySkirt, name: "Satin skirt", category: .bottom, colors: [.purple], instanceCount: 1,
            largestInstanceShare: 1, softEdgeRatio: 0.08),
        Sample(
            scene: .darkOnDark, name: "Black slip dress", category: .dress, colors: [.black], instanceCount: 1,
            largestInstanceShare: 1, softEdgeRatio: 0.07),
        Sample(
            scene: .cutOffTrousers, name: "Dark trousers", category: .bottom, colors: [.brown], instanceCount: 1,
            largestInstanceShare: 1, softEdgeRatio: 0.04),
        Sample(
            scene: .whiteOnWhite, name: "White tee", category: .top, colors: [.white], instanceCount: 1,
            largestInstanceShare: 1, softEdgeRatio: 0.34),
        Sample(
            scene: .teeAndShoes, name: "Green tee and shoes", category: .top, colors: [.green], instanceCount: 3,
            largestInstanceShare: 0.62, softEdgeRatio: 0.05),
    ]

    /// The photo's reference for a scene.
    public static func photo(_ scene: SyntheticGarmentPhotos.Scene) -> PhotoReference {
        .sample("photo:\(scene.rawValue)")
    }

    /// The cutout's reference for a scene.
    public static func cutout(_ scene: SyntheticGarmentPhotos.Scene) -> PhotoReference {
        .sample("cutout:\(scene.rawValue)")
    }

    /// The scene a sample reference names, and whether it's the cutout.
    static func scene(for reference: PhotoReference) -> (scene: SyntheticGarmentPhotos.Scene, isCutout: Bool)? {
        guard case .sample(let name) = reference else { return nil }
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let scene = SyntheticGarmentPhotos.Scene(rawValue: parts[1]) else { return nil }
        switch parts[0] {
        case "photo": return (scene, false)
        case "cutout": return (scene, true)
        default: return nil
        }
    }

    /// The sample pieces, added a day apart before `now`, newest first in the closet.
    public static func garments(now: Date) -> [Garment] {
        samples.enumerated().map { index, sample in
            Garment(
                id: Garment.ID("g-photo-\(sample.scene.rawValue)"),
                name: sample.name,
                category: sample.category,
                colors: sample.colors,
                notes: "A drawn sample photo",
                photo: photo(sample.scene),
                cutout: GarmentCutout(image: cutout(sample.scene), quality: quality(for: sample)),
                addedAt: now.addingTimeInterval(-Double(index + 1) * 86_400)
            )
        }
    }

    /// The signals: coverage, edges and bounds read from the drawing, the rest from `sample`.
    static func quality(for sample: Sample) -> CutoutQuality {
        let measured = measure(sample.scene)
        return CutoutQuality(
            instanceCount: sample.instanceCount,
            coverage: measured.coverage,
            largestInstanceShare: sample.largestInstanceShare,
            touchedEdges: measured.edges,
            softEdgeRatio: sample.softEdgeRatio,
            subjectBounds: measured.bounds)
    }

    /// Reads the garments' share of the picture, the edges they touch and their bounds from a
    /// small transparent drawing of the scene.
    static func measure(_ scene: SyntheticGarmentPhotos.Scene) -> (
        coverage: Double, edges: CutoutEdges, bounds: CutoutBounds
    ) {
        let width = 200
        let height = 250
        guard let image = SyntheticGarmentPhotos.draw(scene, width: width, height: height, background: false),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
            let data = context.data
        else { return (0, [], .whole) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let alpha = data.bindMemory(to: UInt8.self, capacity: width * height)
        var count = 0
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha[y * context.bytesPerRow + x] > 127 {
                count += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard count > 0 else { return (0, [], .whole) }
        var edges: CutoutEdges = []
        if minY <= 1 { edges.insert(.top) }
        if maxY >= height - 2 { edges.insert(.bottom) }
        if minX <= 1 { edges.insert(.left) }
        if maxX >= width - 2 { edges.insert(.right) }
        let bounds = CutoutBounds(
            x: Double(minX) / Double(width), y: Double(minY) / Double(height),
            width: Double(maxX - minX + 1) / Double(width), height: Double(maxY - minY + 1) / Double(height))
        return (Double(count) / Double(width * height), edges, bounds)
    }
}
