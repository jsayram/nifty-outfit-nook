import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Models
import UniformTypeIdentifiers
import Vision

/// Lifts a garment out of its photo on the device with Vision's foreground instance mask
/// (`VNGenerateForegroundInstanceMaskRequest`, the same subject lifting the Photos app uses).
///
/// Steps: read the photo at a working size, find every foreground subject, mask and crop to
/// them, read the quality signals, and write a PNG. It runs off the main actor, stops between
/// steps when its task is cancelled, and cancels Vision's request mid-run. Nothing leaves the
/// device and nothing is logged. See `docs/cutout-feasibility.md`.
public struct VisionCutoutService: CutoutService {
    public struct Options: Hashable, Sendable {
        /// The working size: the photo is shrunk to this on its long side before Vision sees it.
        public var maxPixelSize: Int
        /// Photos with more pixels than this are refused without being decoded.
        public var maxSourcePixels: Int

        public init(maxPixelSize: Int, maxSourcePixels: Int = 100_000_000) {
            self.maxPixelSize = maxPixelSize
            self.maxSourcePixels = maxSourcePixels
        }

        /// The Phase 8a proposal: 1,536 pixels on the long side, enough for a sticker drawn
        /// about 500 points wide on a 3x screen.
        public static let standard = Options(maxPixelSize: 1536)
    }

    public var options: Options

    public init(options: Options = .standard) {
        self.options = options
    }

    @concurrent
    public func cutout(from imageData: Data) async throws(CutoutError) -> CutoutResult {
        let clock = ContinuousClock()
        var timings = CutoutTimings()

        let start = clock.now
        let image = try ImageDownsampler.image(
            from: imageData, maxPixelSize: options.maxPixelSize, maxSourcePixels: options.maxSourcePixels)
        timings.decode = clock.now - start
        if Task.isCancelled { throw .cancelled }
        #if targetEnvironment(simulator)
            // The simulator can't be trusted with this request. On an Apple-silicon Mac (iOS 26.5
            // and 27.0) Vision fails with "Could not create inference context"; on GitHub's macOS
            // runners it runs and finds no subject in a plain flat lay. Saying "unsupported" every
            // time is honest and the same everywhere. The photo is still read first, so bad input
            // gets the same answer as on a device.
            throw .unsupported
        #else
            return try await lift(image, timings: timings, clock: clock)
        #endif
    }

    /// Lifts, masks, measures and encodes. Only reached on a device.
    private func lift(_ image: CGImage, timings: CutoutTimings, clock: ContinuousClock) async throws(CutoutError)
        -> CutoutResult
    {
        var timings = timings
        var start = clock.now
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try await Self.perform(request, on: handler)
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw .noSubject
        }
        timings.lift = clock.now - start
        if Task.isCancelled { throw .cancelled }

        start = clock.now
        let masked: CVPixelBuffer
        do {
            masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
        } catch {
            throw Self.cutoutError(for: error)
        }
        guard let layout = MaskSignals.layout(of: observation.instanceMask) else { throw .noSubject }
        let quality = CutoutQuality(
            instanceCount: observation.allInstances.count,
            coverage: layout.coverage,
            largestInstanceShare: layout.largestInstanceShare,
            touchedEdges: layout.touchedEdges,
            softEdgeRatio: MaskSignals.softEdgeRatio(alphaHistogram: MaskSignals.alphaHistogram(of: masked)),
            subjectBounds: layout.bounds
        )
        guard let cutout = Self.cgImage(from: masked, colorSpace: image.colorSpace) else { throw .failed }
        timings.render = clock.now - start
        if Task.isCancelled { throw .cancelled }

        start = clock.now
        guard let png = Self.png(from: cutout) else { throw .failed }
        timings.encode = clock.now - start

        return CutoutResult(
            imageData: png, pixelWidth: cutout.width, pixelHeight: cutout.height, quality: quality, timings: timings)
    }

    // MARK: Steps

    /// Runs the request, cancelling it if the task is cancelled while Vision works.
    private static func perform(
        _ request: VNGenerateForegroundInstanceMaskRequest, on handler: VNImageRequestHandler
    ) async throws(CutoutError) {
        // Vision documents `cancel()` as the way to stop a running request from another thread.
        nonisolated(unsafe) let running = request
        do {
            try await withTaskCancellationHandler {
                try handler.perform([request])
            } onCancel: {
                running.cancel()
            }
        } catch {
            throw Task.isCancelled ? .cancelled : cutoutError(for: error)
        }
    }

    /// Maps Vision's errors onto the cases a screen can act on.
    static func cutoutError(for error: any Error) -> CutoutError {
        let error = error as NSError
        guard error.domain == VNErrorDomain, let code = VNErrorCode(rawValue: error.code) else { return .failed }
        switch code {
        case .requestCancelled: return .cancelled
        case .unsupportedRequest, .unsupportedRevision, .unsupportedComputeStage, .unsupportedComputeDevice:
            return .unsupported
        case .invalidImage, .invalidFormat: return .unreadableImage
        default: return .failed
        }
    }

    /// A copy of Vision's premultiplied BGRA buffer as a `CGImage`, in the photo's colour space.
    private static func cgImage(from buffer: CVPixelBuffer, colorSpace: CGColorSpace?) -> CGImage? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0,
            let provider = CGDataProvider(data: Data(bytes: base, count: bytesPerRow * height) as CFData)
        else { return nil }
        let space =
            colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// A PNG with no metadata: nothing from the original photo's EXIF, GPS or TIFF data.
    private static func png(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
