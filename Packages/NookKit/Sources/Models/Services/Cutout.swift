import Foundation

// Lifting a garment out of its photo (Phase 8a). The result is the piece on a transparent
// background, plus simple signals that say how clean the lift looks, so a screen can choose
// between the sticker look and the rounded-tile fallback (RD-07, Phase 8b).

/// Cuts the main subject out of a photo.
///
/// Phase 8a has an on-device implementation that uses Apple's Vision framework (in the
/// `Services` module) and a stand-in for Stage A screens and tests (in Fixtures). Nothing
/// leaves the phone.
public protocol CutoutService: Sendable {
    /// The subject of `imageData` (JPEG, HEIC, PNG and the other formats ImageIO reads) on a
    /// transparent background, cropped to the subject.
    func cutout(from imageData: Data) async throws(CutoutError) -> CutoutResult
}

/// Why there's no cutout.
public enum CutoutError: Error, Hashable, Sendable {
    /// The bytes aren't a picture ImageIO can read.
    case unreadableImage
    /// The picture is larger than the safety limit, so it wasn't decoded.
    case imageTooLarge
    /// Nothing in the picture stood out as a subject.
    case noSubject
    /// This device can't run subject lifting (for example a simulator without the Neural Engine).
    case unsupported
    /// Subject lifting ran and failed for another reason.
    case failed
    case cancelled
}

/// A lifted subject.
public struct CutoutResult: Hashable, Sendable {
    /// A PNG of the subject on a transparent background, cropped to the subject. It carries no
    /// metadata from the original photo (no location, no camera details).
    public var imageData: Data
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var quality: CutoutQuality
    /// How long each step took. For measuring only; nothing is logged.
    public var timings: CutoutTimings

    public init(
        imageData: Data, pixelWidth: Int, pixelHeight: Int, quality: CutoutQuality,
        timings: CutoutTimings = CutoutTimings()
    ) {
        self.imageData = imageData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.quality = quality
        self.timings = timings
    }
}

/// Signals about how clean a cutout looks. None of them decides anything on its own;
/// `CutoutThresholds` turns them into a suggestion.
public struct CutoutQuality: Hashable, Sendable, Codable {
    /// How many separate subjects were found. Every one of them is in the cutout.
    public var instanceCount: Int
    /// The share of the picture the subject covers, from 0 to 1.
    public var coverage: Double
    /// The largest subject's share of everything that was lifted, from 0 to 1. Near 1 means
    /// one main thing; lower means several things of similar size.
    public var largestInstanceShare: Double
    /// The picture's edges the subject touches. A garment that runs off the photo looks cut off
    /// as a sticker.
    public var touchedEdges: CutoutEdges
    /// The share of the subject's mask that's neither clearly in nor clearly out, from 0 to 1.
    /// High means fuzzy or unsure edges, as with white on white.
    public var softEdgeRatio: Double
    /// Where the subject sits in the picture, as fractions of its width and height, origin top left.
    public var subjectBounds: CutoutBounds

    public init(
        instanceCount: Int,
        coverage: Double,
        largestInstanceShare: Double,
        touchedEdges: CutoutEdges,
        softEdgeRatio: Double,
        subjectBounds: CutoutBounds
    ) {
        self.instanceCount = instanceCount
        self.coverage = coverage
        self.largestInstanceShare = largestInstanceShare
        self.touchedEdges = touchedEdges
        self.softEdgeRatio = softEdgeRatio
        self.subjectBounds = subjectBounds
    }
}

/// The edges of a picture.
public struct CutoutEdges: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let top = CutoutEdges(rawValue: 1 << 0)
    public static let bottom = CutoutEdges(rawValue: 1 << 1)
    public static let left = CutoutEdges(rawValue: 1 << 2)
    public static let right = CutoutEdges(rawValue: 1 << 3)

    public var count: Int { rawValue.nonzeroBitCount }
}

/// A rectangle as fractions of a picture's width and height, origin top left.
public struct CutoutBounds: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let whole = CutoutBounds(x: 0, y: 0, width: 1, height: 1)
}

/// How long each step of a cutout took.
public struct CutoutTimings: Hashable, Sendable {
    /// Reading the photo and shrinking it to the working size.
    public var decode: Duration
    /// Vision finding the subject.
    public var lift: Duration
    /// Masking, cropping and reading the quality signals.
    public var render: Duration
    /// Writing the PNG.
    public var encode: Duration

    public init(decode: Duration = .zero, lift: Duration = .zero, render: Duration = .zero, encode: Duration = .zero) {
        self.decode = decode
        self.lift = lift
        self.render = render
        self.encode = encode
    }

    public var total: Duration { decode + lift + render + encode }
}
