import CoreVideo
import Foundation
import Models
import Testing

@testable import Services

/// The quality signals, read from hand-made masks so they don't need Vision.
struct MaskSignalsTests {
    /// One subject's rectangle in a label mask.
    private struct Fill {
        var label: UInt8 = 1
        var x: Int
        var y: Int
        var width: Int
        var height: Int
    }

    /// A width x height label mask with each fill's label in its rectangle.
    private func mask(width: Int, height: Int, padding: Int = 0, _ fills: [Fill]) -> (bytes: [UInt8], bytesPerRow: Int)
    {
        let bytesPerRow = width + padding
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        for fill in fills {
            for row in fill.y..<(fill.y + fill.height) {
                for column in fill.x..<(fill.x + fill.width) { bytes[row * bytesPerRow + column] = fill.label }
            }
        }
        return (bytes, bytesPerRow)
    }

    private func layout(width: Int, height: Int, padding: Int = 0, _ fills: [Fill]) -> MaskSignals.Layout? {
        let (bytes, bytesPerRow) = mask(width: width, height: height, padding: padding, fills)
        return bytes.withUnsafeBytes {
            MaskSignals.layout(labels: $0, width: width, height: height, bytesPerRow: bytesPerRow)
        }
    }

    @Test func oneSubjectInTheMiddle() throws {
        let result = try #require(layout(width: 100, height: 100, [Fill(x: 25, y: 20, width: 50, height: 60)]))
        #expect(result.coverage == 0.3)
        #expect(result.largestInstanceShare == 1)
        #expect(result.touchedEdges.isEmpty)
        #expect(result.bounds == CutoutBounds(x: 0.25, y: 0.2, width: 0.5, height: 0.6))
    }

    @Test func rowPaddingIsSkipped() throws {
        // Vision's buffers can have more bytes per row than pixels. Padding bytes aren't pixels.
        var (bytes, bytesPerRow) = mask(width: 10, height: 10, padding: 6, [Fill(x: 0, y: 0, width: 5, height: 10)])
        for row in 0..<10 {
            for pad in 10..<16 { bytes[row * bytesPerRow + pad] = 9 }
        }
        let result = try #require(
            bytes.withUnsafeBytes { MaskSignals.layout(labels: $0, width: 10, height: 10, bytesPerRow: bytesPerRow) })
        #expect(result.coverage == 0.5)
        #expect(result.touchedEdges == [.top, .bottom, .left])
    }

    @Test func severalSubjectsShareTheCoverage() throws {
        let result = try #require(
            layout(
                width: 100, height: 100,
                [Fill(x: 10, y: 10, width: 30, height: 30), Fill(label: 2, x: 60, y: 60, width: 20, height: 10)]))
        #expect(result.coverage == 0.11)
        #expect(abs(result.largestInstanceShare - 900.0 / 1100.0) < 1e-9)
        #expect(result.bounds == CutoutBounds(x: 0.1, y: 0.1, width: 0.7, height: 0.6))
    }

    @Test func edgesCountWithinTheMargin() throws {
        let margin = MaskSignals.edgeMargin
        let near = try #require(layout(width: 100, height: 100, [Fill(x: margin - 1, y: 30, width: 10, height: 70)]))
        #expect(near.touchedEdges == [.left, .bottom])
        let clear = try #require(
            layout(
                width: 100, height: 100, [Fill(x: margin, y: margin, width: 100 - 2 * margin, height: 100 - 2 * margin)]
            ))
        #expect(clear.touchedEdges.isEmpty)
        let full = try #require(layout(width: 100, height: 100, [Fill(x: 0, y: 0, width: 100, height: 100)]))
        #expect(full.touchedEdges == [.top, .bottom, .left, .right])
        #expect(full.touchedEdges.count == 4)
    }

    @Test func anEmptyOrBrokenMaskHasNoLayout() {
        #expect(layout(width: 50, height: 50, []) == nil)
        let bytes = [UInt8](repeating: 1, count: 10)
        #expect(bytes.withUnsafeBytes { MaskSignals.layout(labels: $0, width: 10, height: 10, bytesPerRow: 10) } == nil)
        #expect(bytes.withUnsafeBytes { MaskSignals.layout(labels: $0, width: 0, height: 0, bytesPerRow: 0) } == nil)
    }

    @Test func softEdgesAreTheMiddleAlphas() {
        var histogram = [UInt](repeating: 0, count: 256)
        histogram[0] = 5_000  // background, ignored
        histogram[10] = 100  // almost clear, ignored
        histogram[128] = 100  // soft
        histogram[250] = 800  // solid
        histogram[255] = 100  // solid
        #expect(MaskSignals.softEdgeRatio(alphaHistogram: histogram) == 0.1)
        #expect(MaskSignals.softEdgeRatio(alphaHistogram: [UInt](repeating: 0, count: 256)) == 0)
        #expect(MaskSignals.softEdgeRatio(alphaHistogram: []) == 0)
    }

    @Test func pixelBuffersAreReadLikeVisionsOwn() throws {
        var labels: CVPixelBuffer?
        CVPixelBufferCreate(nil, 8, 4, kCVPixelFormatType_OneComponent8, nil, &labels)
        let labelBuffer = try #require(labels)
        CVPixelBufferLockBaseAddress(labelBuffer, [])
        let labelBytes = try #require(CVPixelBufferGetBaseAddress(labelBuffer)).assumingMemoryBound(to: UInt8.self)
        let labelRow = CVPixelBufferGetBytesPerRow(labelBuffer)
        for y in 0..<4 {
            for x in 0..<8 { labelBytes[y * labelRow + x] = (x >= 4 && y >= 2) ? 1 : 0 }
        }
        CVPixelBufferUnlockBaseAddress(labelBuffer, [])
        let layout = try #require(MaskSignals.layout(of: labelBuffer))
        #expect(layout.coverage == 0.25)
        #expect(layout.touchedEdges == [.bottom, .right])

        var image: CVPixelBuffer?
        CVPixelBufferCreate(nil, 4, 2, kCVPixelFormatType_32BGRA, nil, &image)
        let imageBuffer = try #require(image)
        CVPixelBufferLockBaseAddress(imageBuffer, [])
        let pixels = try #require(CVPixelBufferGetBaseAddress(imageBuffer)).assumingMemoryBound(to: UInt8.self)
        let imageRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let alphas: [UInt8] = [0, 0, 128, 255, 255, 255, 255, 0]
        for (index, alpha) in alphas.enumerated() {
            pixels[(index / 4) * imageRow + (index % 4) * 4 + 3] = alpha
        }
        CVPixelBufferUnlockBaseAddress(imageBuffer, [])
        let histogram = MaskSignals.alphaHistogram(of: imageBuffer)
        #expect(histogram.count == 256)
        #expect(histogram[0] == 3 && histogram[128] == 1 && histogram[255] == 4)
        #expect(MaskSignals.softEdgeRatio(alphaHistogram: histogram) == 0.2)

        // The wrong pixel format reads as nothing rather than as garbage.
        #expect(MaskSignals.layout(of: imageBuffer) == nil)
        #expect(MaskSignals.alphaHistogram(of: labelBuffer).isEmpty)
    }
}
