#if DEBUG
    import DesignSystem
    import ImageIO
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers

    /// A stand-in for choosing a screenshot, for debug builds and UI tests, which can't drive the
    /// system photo picker. With the launch argument `-feedback-sample-screenshot`, Send feedback
    /// shows one more row, "Attach a sample screenshot". It makes a screenshot-sized picture with
    /// made-up metadata (a place, a camera, a caption, a comment), exactly the kind a real
    /// screenshot or photo can carry, and hands it to the same code the picker's result goes
    /// through, so the checkpoint can see that every bit of it is removed before it is sent.
    enum FeedbackSampleScreenshot {
        static let launchArgument = "-feedback-sample-screenshot"
        static var isOn: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

        /// The row, or nothing when the launch argument isn't there.
        @MainActor @ViewBuilder
        static func button(_ attach: @escaping (Data) -> Void) -> some View {
            if isOn {
                Button {
                    attach(jpegWithMetadata())
                } label: {
                    NookRow("Attach a sample screenshot", subtitle: "Test build only", systemImage: "wand.and.stars")
                }
                .buttonStyle(.nookRow)
                .accessibilityIdentifier("feedback.screenshot.sample")
            }
        }

        /// A 1170 x 2532 picture (an iPhone 12 screenshot) as a JPEG that carries Exif, GPS, TIFF
        /// and IPTC metadata.
        @MainActor
        static func jpegWithMetadata() -> Data {
            let size = CGSize(width: 390, height: 844)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor(red: 0.96, green: 0.92, blue: 0.86, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor(red: 0.55, green: 0.32, blue: 0.25, alpha: 1).setFill()
                context.fill(CGRect(x: 24, y: 120, width: 342, height: 220))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: UIColor.darkGray,
                ]
                "Sample screenshot".draw(at: CGPoint(x: 24, y: 380), withAttributes: attributes)
            }
            let data = NSMutableData()
            guard let cgImage = image.cgImage,
                let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
            else { return Data() }
            let properties: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.9,
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifUserComment: "Taken at home",
                    kCGImagePropertyExifDateTimeOriginal: "2026:10:21 09:30:00",
                ],
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 47.6062, kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 122.3321, kCGImagePropertyGPSLongitudeRef: "W",
                ],
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 12",
                ],
                kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCaptionAbstract: "A private caption"],
            ]
            CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return Data() }
            return data as Data
        }
    }
#endif
