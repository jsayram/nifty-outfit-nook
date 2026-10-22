import CoreGraphics
import Foundation
import Vision

/// A face found in a picture, in its pixels (origin top left).
public struct DetectedFace: Sendable, Equatable {
    public var box: CGRect
    public var confidence: Float
    /// The lowest point of the face's outline (her chin), when landmarks found it.
    public var chinY: Double?

    public init(box: CGRect, confidence: Float, chinY: Double? = nil) {
        self.box = box
        self.confidence = confidence
        self.chinY = chinY
    }
}

/// Where her neck and shoulders are, in pixels (origin top left).
public struct BodyPose: Sendable, Equatable {
    public var neck: CGPoint
    public var leftShoulder: CGPoint?
    public var rightShoulder: CGPoint?

    public init(neck: CGPoint, leftShoulder: CGPoint? = nil, rightShoulder: CGPoint? = nil) {
        self.neck = neck
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
    }

    /// The distance between her shoulders, when both were found.
    var shoulderWidth: Double? {
        guard let leftShoulder, let rightShoulder else { return nil }
        return hypot(leftShoulder.x - rightShoulder.x, leftShoulder.y - rightShoulder.y)
    }
}

/// What the phone found in her try-on photo.
public struct PersonAnalysis: Sendable, Equatable {
    /// Her outline (every person's, if there are several), the picture's size, 255 inside.
    public var matte: TryOnMask
    public var faces: [DetectedFace]
    public var pose: BodyPose?

    public init(matte: TryOnMask, faces: [DetectedFace], pose: BodyPose?) {
        self.matte = matte
        self.faces = faces
        self.pose = pose
    }
}

/// The analysis failed to run. The try-on doesn't run either (fail closed).
public struct PersonAnalysisFailed: Error, Sendable, Equatable {
    public init() {}
}

/// Finds her outline, her face and her pose. Apple Vision on an iPhone (`VisionPersonAnalyzer`);
/// simulators can't run those requests ("Could not create inference context", "E5RT is not
/// supported"), so simulator tests and the debug checkpoint use `SyntheticPersonAnalyzer`.
public protocol PersonAnalyzing: Sendable {
    func analyze(_ image: TryOnBitmap) async throws(PersonAnalysisFailed) -> PersonAnalysis
    /// Every face it can find, for the check after masking: there must be none.
    func faces(in image: TryOnBitmap) async throws(PersonAnalysisFailed) -> [DetectedFace]
    /// Her neck and shoulders, or `nil` when they can't be found.
    func pose(in image: TryOnBitmap) async -> BodyPose?
}

/// Apple Vision on the device: person segmentation (accurate), face rectangles and landmarks, and
/// body pose. Any error is a failure: the try-on doesn't run.
public struct VisionPersonAnalyzer: PersonAnalyzing {
    public init() {}

    public func analyze(_ image: TryOnBitmap) async throws(PersonAnalysisFailed) -> PersonAnalysis {
        try await Self.run(image)
    }

    public func faces(in image: TryOnBitmap) async throws(PersonAnalysisFailed) -> [DetectedFace] {
        try await Self.detectFaces(image)
    }

    public func pose(in image: TryOnBitmap) async -> BodyPose? {
        await Self.detectPose(image)
    }

    @concurrent
    private static func run(_ bitmap: TryOnBitmap) async throws(PersonAnalysisFailed) -> PersonAnalysis {
        guard let image = bitmap.cgImage else { throw PersonAnalysisFailed() }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = .accurate
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try handler.perform([segmentation])
        } catch {
            throw PersonAnalysisFailed()
        }
        guard let buffer = segmentation.results?.first?.pixelBuffer, let matte = mask(from: buffer) else {
            throw PersonAnalysisFailed()
        }
        let faces = try faces(in: image, width: bitmap.width, height: bitmap.height)
        return PersonAnalysis(
            matte: matte.resized(width: bitmap.width, height: bitmap.height), faces: faces,
            pose: pose(in: image, width: bitmap.width, height: bitmap.height))
    }

    @concurrent
    private static func detectFaces(_ bitmap: TryOnBitmap) async throws(PersonAnalysisFailed) -> [DetectedFace] {
        guard let image = bitmap.cgImage else { throw PersonAnalysisFailed() }
        return try faces(in: image, width: bitmap.width, height: bitmap.height)
    }

    @concurrent
    private static func detectPose(_ bitmap: TryOnBitmap) async -> BodyPose? {
        guard let image = bitmap.cgImage else { return nil }
        return pose(in: image, width: bitmap.width, height: bitmap.height)
    }

    /// Face rectangles, then landmarks for the chin. Both requests run; an error fails.
    private static func faces(in image: CGImage, width: Int, height: Int) throws(PersonAnalysisFailed) -> [DetectedFace] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let rectangles = VNDetectFaceRectanglesRequest()
        let landmarks = VNDetectFaceLandmarksRequest()
        do {
            try handler.perform([rectangles, landmarks])
        } catch {
            throw PersonAnalysisFailed()
        }
        let size = CGSize(width: width, height: height)
        let chins: [(box: CGRect, chinY: Double)] = (landmarks.results ?? []).compactMap { face in
            guard let contour = face.landmarks?.faceContour else { return nil }
            // Vision's points have their origin at the bottom left: the chin is the lowest y.
            guard let lowest = contour.pointsInImage(imageSize: size).map(\.y).min() else { return nil }
            return (face.boundingBox, Double(height) - lowest)
        }
        return (rectangles.results ?? []).map { face in
            let box = VNImageRectForNormalizedRect(face.boundingBox, width, height)
            let flipped = CGRect(x: box.minX, y: Double(height) - box.maxY, width: box.width, height: box.height)
            let chin = chins.first { $0.box.intersects(face.boundingBox) }?.chinY
            return DetectedFace(box: flipped, confidence: face.confidence, chinY: chin)
        }
    }

    private static func pose(in image: CGImage, width: Int, height: Int) -> BodyPose? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNDetectHumanBodyPoseRequest()
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first,
            let points = try? observation.recognizedPoints(.all)
        else { return nil }
        func point(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let found = points[name], found.confidence > 0.3 else { return nil }
            return CGPoint(x: found.location.x * Double(width), y: (1 - found.location.y) * Double(height))
        }
        guard let neck = point(.neck) else { return nil }
        return BodyPose(neck: neck, leftShoulder: point(.leftShoulder), rightShoulder: point(.rightShoulder))
    }

    /// Vision's matte (one 8-bit channel) as a mask at its own size.
    private static func mask(from buffer: CVPixelBuffer) -> TryOnMask? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8,
            let base = CVPixelBufferGetBaseAddress(buffer)
        else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var values = [UInt8](repeating: 0, count: width * height)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width { values[y * width + x] = bytes[y * stride + x] }
        }
        return TryOnMask(width: width, height: height, values: values)
    }
}
