import Accelerate
import CoreVideo
import Foundation
import Models

/// Reads the quality signals from Vision's masks. The arithmetic is kept apart from Vision so
/// tests can feed it hand-made masks.
enum MaskSignals {
    /// What the instance mask says: coverage, how the subjects compare, the edges they touch and
    /// where they are.
    struct Layout: Hashable {
        var coverage: Double
        var largestInstanceShare: Double
        var touchedEdges: CutoutEdges
        var bounds: CutoutBounds
    }

    /// A subject pixel this close to a border (in mask pixels) counts as touching it. Vision's
    /// instance mask is about 512 pixels across, so 2 pixels is under half a percent.
    static let edgeMargin = 2

    /// Reads a label mask: one byte per pixel, 0 for background and 1 or more for each subject,
    /// rows top to bottom. Returns `nil` when no pixel belongs to a subject.
    static func layout(labels: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int) -> Layout? {
        guard width > 0, height > 0, bytesPerRow >= width, labels.count >= bytesPerRow * (height - 1) + width
        else { return nil }
        var counts = [Int](repeating: 0, count: 256)
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1
        for y in 0..<height {
            let row = y * bytesPerRow
            var rowHasSubject = false
            for x in 0..<width {
                let label = labels[row + x]
                guard label != 0 else { continue }
                counts[Int(label)] += 1
                rowHasSubject = true
                if x < minX { minX = x }
                if x > maxX { maxX = x }
            }
            if rowHasSubject {
                if y < minY { minY = y }
                maxY = y
            }
        }
        let subject = counts.dropFirst().reduce(0, +)
        guard subject > 0 else { return nil }

        var edges: CutoutEdges = []
        if minY < edgeMargin { edges.insert(.top) }
        if maxY >= height - edgeMargin { edges.insert(.bottom) }
        if minX < edgeMargin { edges.insert(.left) }
        if maxX >= width - edgeMargin { edges.insert(.right) }

        return Layout(
            coverage: Double(subject) / Double(width * height),
            largestInstanceShare: Double(counts.dropFirst().max() ?? 0) / Double(subject),
            touchedEdges: edges,
            bounds: CutoutBounds(
                x: Double(minX) / Double(width),
                y: Double(minY) / Double(height),
                width: Double(maxX - minX + 1) / Double(width),
                height: Double(maxY - minY + 1) / Double(height)
            )
        )
    }

    /// Reads a one-byte-per-pixel label mask from Vision.
    static func layout(of mask: CVPixelBuffer) -> Layout? {
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8 else { return nil }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        return layout(
            labels: UnsafeRawBufferPointer(start: base, count: bytesPerRow * height),
            width: CVPixelBufferGetWidth(mask), height: height, bytesPerRow: bytesPerRow)
    }

    /// Alpha values from 0 to this are outside the subject, and from 255 minus this up are inside.
    /// Everything between is a soft edge.
    static let softAlphaMargin = 25

    /// The share of the subject's pixels that are soft, from a 256-bucket alpha histogram.
    static func softEdgeRatio(alphaHistogram: [UInt]) -> Double {
        guard alphaHistogram.count == 256 else { return 0 }
        let soft = alphaHistogram[(softAlphaMargin + 1)..<(255 - softAlphaMargin)].reduce(0, +)
        let solid = alphaHistogram[(255 - softAlphaMargin)...].reduce(0, +)
        guard soft + solid > 0 else { return 0 }
        return Double(soft) / Double(soft + solid)
    }

    /// The alpha histogram of a 32-bit BGRA buffer, counted with Accelerate.
    static func alphaHistogram(of buffer: CVPixelBuffer) -> [UInt] {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return [] }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        var image = vImage_Buffer(
            data: base,
            height: vImagePixelCount(CVPixelBufferGetHeight(buffer)),
            width: vImagePixelCount(CVPixelBufferGetWidth(buffer)),
            rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        var blue = [vImagePixelCount](repeating: 0, count: 256)
        var green = blue
        var red = blue
        var alpha = blue
        let status = blue.withUnsafeMutableBufferPointer { blue in
            green.withUnsafeMutableBufferPointer { green in
                red.withUnsafeMutableBufferPointer { red in
                    alpha.withUnsafeMutableBufferPointer { alpha in
                        var channels: [UnsafeMutablePointer<vImagePixelCount>?] = [
                            blue.baseAddress, green.baseAddress, red.baseAddress, alpha.baseAddress,
                        ]
                        return vImageHistogramCalculation_ARGB8888(&image, &channels, vImage_Flags(kvImageNoFlags))
                    }
                }
            }
        }
        guard status == kvImageNoError else { return [] }
        return alpha.map { UInt($0) }
    }
}
