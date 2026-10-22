import CoreGraphics
import CoreVideo
import Foundation
import Models
import Vision

/// Apple Vision on a camera frame or a photo, for the try-on photo's guidance (Phase 33b): body
/// pose (where her head, shoulders, wrists, hips and ankles are), person segmentation (her outline)
/// and how bright she and the frame are. Runs on the phone and keeps nothing. Where Vision can't
/// run (simulators: "Could not create inference context") it answers `nil`, and the guidance says
/// it can't see her yet.
public struct VisionFrameAnalyzer: FrameAnalyzing {
    public init() {}

    public func observe(_ frame: AnalysisFrame) async -> FramingObservation? {
        await Self.run(frame)
    }

    /// The grid the brightness is read from: small, since only averages are needed.
    private static let gridWidth = 40

    @concurrent
    private static func run(_ frame: AnalysisFrame) async -> FramingObservation? {
        let handler: VNImageRequestHandler
        let quality: VNGeneratePersonSegmentationRequest.QualityLevel
        switch frame.source {
        case .buffer(let buffer):
            handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
            quality = .fast
        case .image(let image):
            handler = VNImageRequestHandler(cgImage: image, options: [:])
            quality = .balanced
        }
        let pose = VNDetectHumanBodyPoseRequest()
        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = quality
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try handler.perform([pose, segmentation])
        } catch {
            return nil
        }
        let matte = segmentation.results?.first.flatMap { matte(from: $0.pixelBuffer) }
        let outline = matte.flatMap(bounds(of:))
        let (size, luma) = lumaGrid(of: frame)
        let people = pose.results?.count ?? 0
        let body = (pose.results ?? []).max { score($0) < score($1) }
        // Her outline with no body pose is somebody the pose tracking can't read (cut off, turned
        // away): that's still one person in view.
        let seen = people > 0 ? people : (outline == nil ? 0 : 1)
        var brightness = 0.5
        var subject: Double?
        if let luma {
            brightness = luma.reduce(0, +) / Double(luma.count)
            if let matte {
                var total = 0.0
                var count = 0
                for (index, value) in luma.enumerated() {
                    let nx = (Double(index % gridWidth) + 0.5) / Double(gridWidth)
                    let ny = (Double(index / gridWidth) + 0.5) / Double(size.height)
                    if matte.value(atX: nx, y: ny) >= 128 {
                        total += value
                        count += 1
                    }
                }
                if count > 20 { subject = total / Double(count) }
            }
        }
        return FramingObservation(
            people: seen, joints: body.map(joints(of:)) ?? [:], outline: outline, aspect: aspect(of: frame),
            frameBrightness: brightness, subjectBrightness: subject)
    }

    private static func score(_ observation: VNHumanBodyPoseObservation) -> Float {
        (try? observation.recognizedPoints(.all))?.values.reduce(0) { $0 + $1.confidence } ?? 0
    }

    private static func joints(of observation: VNHumanBodyPoseObservation) -> [FramingObservation.Joint:
        FramingObservation.Point]
    {
        let names: [(FramingObservation.Joint, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye), (.neck, .neck),
            (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder), (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
            (.leftHip, .leftHip), (.rightHip, .rightHip), (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
        ]
        guard let points = try? observation.recognizedPoints(.all) else { return [:] }
        var result: [FramingObservation.Joint: FramingObservation.Point] = [:]
        for (joint, name) in names {
            guard let found = points[name] else { continue }
            // Vision's origin is the bottom left.
            result[joint] = .init(x: found.location.x, y: 1 - found.location.y, confidence: Double(found.confidence))
        }
        return result
    }

    private static func aspect(of frame: AnalysisFrame) -> Double {
        switch frame.source {
        case .buffer(let buffer): Double(CVPixelBufferGetWidth(buffer)) / Double(max(1, CVPixelBufferGetHeight(buffer)))
        case .image(let image): Double(image.width) / Double(max(1, image.height))
        }
    }

    // MARK: Pixels

    /// Vision's matte (one 8-bit channel) at its own size.
    private struct Matte {
        let width: Int
        let height: Int
        let values: [UInt8]

        func value(atX nx: Double, y ny: Double) -> UInt8 {
            let x = min(width - 1, max(0, Int(nx * Double(width))))
            let y = min(height - 1, max(0, Int(ny * Double(height))))
            return values[y * width + x]
        }
    }

    private static func matte(from buffer: CVPixelBuffer) -> Matte? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8,
            let base = CVPixelBufferGetBaseAddress(buffer)
        else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { values[y * width + x] = bytes[y * stride + x] }
        }
        return Matte(width: width, height: height, values: values)
    }

    /// The box around her outline as shares of the frame, ignoring specks.
    private static func bounds(of matte: Matte) -> CGRect? {
        var minX = matte.width
        var maxX = -1
        var minY = matte.height
        var maxY = -1
        var count = 0
        for y in 0..<matte.height {
            for x in 0..<matte.width where matte.values[y * matte.width + x] >= 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                count += 1
            }
        }
        // Less than half a percent of the frame is noise, not a person.
        guard maxX >= minX, count * 200 > matte.width * matte.height else { return nil }
        let w = Double(matte.width)
        let h = Double(matte.height)
        return CGRect(
            x: Double(minX) / w, y: Double(minY) / h, width: Double(maxX - minX + 1) / w,
            height: Double(maxY - minY + 1) / h)
    }

    /// Brightness (0 to 1) of a coarse grid over the frame, row by row, and the grid's size.
    /// `nil` brightness when the frame's pixel format isn't one this reads.
    private static func lumaGrid(of frame: AnalysisFrame) -> (size: (width: Int, height: Int), luma: [Double]?) {
        switch frame.source {
        case .image(let image):
            let height = max(1, gridWidth * image.height / max(1, image.width))
            var pixels = [UInt8](repeating: 0, count: gridWidth * height * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: gridWidth, height: height, bitsPerComponent: 8,
                        bytesPerRow: gridWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                else { return false }
                context.interpolationQuality = .low
                context.draw(image, in: CGRect(x: 0, y: 0, width: gridWidth, height: height))
                return true
            }
            guard drawn else { return ((gridWidth, height), nil) }
            let luma = (0..<(gridWidth * height)).map { index in
                luminance(Double(pixels[index * 4]), Double(pixels[index * 4 + 1]), Double(pixels[index * 4 + 2]))
            }
            return ((gridWidth, height), luma)
        case .buffer(let buffer):
            let width = CVPixelBufferGetWidth(buffer)
            let sourceHeight = CVPixelBufferGetHeight(buffer)
            let height = max(1, gridWidth * sourceHeight / max(1, width))
            guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else {
                return ((gridWidth, height), nil)
            }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buffer) else { return ((gridWidth, height), nil) }
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            var luma: [Double] = []
            luma.reserveCapacity(gridWidth * height)
            for gy in 0..<height {
                let y = min(sourceHeight - 1, (gy * 2 + 1) * sourceHeight / (height * 2))
                for gx in 0..<gridWidth {
                    let x = min(width - 1, (gx * 2 + 1) * width / (gridWidth * 2))
                    let offset = y * stride + x * 4
                    luma.append(luminance(Double(bytes[offset + 2]), Double(bytes[offset + 1]), Double(bytes[offset])))
                }
            }
            return ((gridWidth, height), luma)
        }
    }

    private static func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
    }
}
