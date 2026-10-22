import CoreGraphics
import Foundation
import ImageIO
import Models
import UniformTypeIdentifiers

// Debug builds only (32b, L9): a Release build has no fake backend to fall back to.
#if DEBUG
    /// How the fake backend's try-on behaves (33a): `-cloud-tryon [normal|slow|fails]` in debug builds.
    public enum FakeTryOnBehaviour: String, Sendable, Equatable {
        /// The picture comes back in the first answer. The default, for the debug limits screen and
        /// tests that aren't about waiting.
        case instant
        /// The picture is ready about 3 seconds after the first ask, which answers "still running".
        case normal
        /// About 15 seconds, so she can leave the screen and see the banner.
        case slow
        /// The job runs and fails: "It didn't work this time. It wasn't counted."
        case fails

        var delay: TimeInterval {
            switch self {
            case .instant: 0
            case .normal, .fails: 3
            case .slow: 15
            }
        }
    }

    /// The fake image service: checks a try-on request the way the backend does, and "dresses" the
    /// faceless photo by drawing the garment photos over its lower half, so the whole path (sending,
    /// waiting, the head going back on) can be tried with no provider. Deterministic: the same
    /// request gives the same picture. It never touches the grey head.
    enum FakeTryOn {
        static let consentVersions: Set<String> = [TryOnConsent.currentVersion]

        /// The backend's own checks on the body (contract.json, TryOnRequest and limits.tryOn).
        static func isValid(_ object: [String: Any], decoded: APIV1.TryOnRequest) -> Bool {
            guard Set(object.keys) == ["contextRevision", "consentVersion", "person", "garments"],
                decoded.contextRevision.wholeMatch(of: /[A-Za-z0-9_-]{1,64}/) != nil,
                (1...TryOnCall.maximumGarments).contains(decoded.garments.count),
                Set(decoded.garments.map(\.id)).count == decoded.garments.count,
                image(decoded.person, maxBytes: 1_500_000) != nil
            else { return false }
            return decoded.garments.allSatisfy {
                GarmentCategory(rawValue: $0.category) != nil && image($0.image, maxBytes: 400_000) != nil
                    && ($0.kind.map { GarmentSubKind(rawValue: $0) != nil } ?? true)
            }
        }

        /// The bytes, when they are what the content type says (JPEG or PNG) and not too large.
        static func image(_ image: APIV1.TryOnImage, maxBytes: Int) -> Data? {
            guard let bytes = Data(base64Encoded: image.data), bytes.count <= maxBytes else { return nil }
            let jpeg = bytes.starts(with: [0xFF, 0xD8, 0xFF])
            let png = bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            switch image.contentType {
            case "image/jpeg": return jpeg ? bytes : nil
            case "image/png": return png ? bytes : nil
            default: return nil
            }
        }

        /// The person with each garment drawn small across her lower half, as a JPEG.
        static func dress(_ request: APIV1.TryOnRequest) -> Data? {
            guard let personBytes = image(request.person, maxBytes: 1_500_000),
                let person = cgImage(personBytes)
            else { return nil }
            let width = person.width
            let height = person.height
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return nil }
            context.draw(person, in: CGRect(x: 0, y: 0, width: width, height: height))
            let garments = request.garments.compactMap { image($0.image, maxBytes: 400_000).flatMap(cgImage) }
            let count = max(1, garments.count)
            let side = min(Double(width) * 0.9 / Double(count), Double(width) * 0.24)
            let gap = side * 0.08
            let total = Double(count) * side + Double(count - 1) * gap
            var x = (Double(width) - total) / 2
            // Core Graphics counts from the bottom: about 40% up from the bottom edge.
            let y = Double(height) * 0.32
            for garment in garments {
                let frame = CGRect(x: x, y: y, width: side, height: side)
                context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                context.fill(frame.insetBy(dx: -3, dy: -3))
                context.draw(garment, in: aspectFit(garment, in: frame))
                x += side + gap
            }
            guard let dressed = context.makeImage() else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(
                destination, dressed, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            return CGImageDestinationFinalize(destination) ? data as Data : nil
        }

        private static func cgImage(_ data: Data) -> CGImage? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        private static func aspectFit(_ image: CGImage, in frame: CGRect) -> CGRect {
            let scale = min(frame.width / Double(image.width), frame.height / Double(image.height))
            let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
            return CGRect(
                x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
        }
    }
#endif
