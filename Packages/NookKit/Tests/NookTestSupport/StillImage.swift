import CoreGraphics
import SwiftUI
import UIKit

/// `content` drawn by SwiftUI's `ImageRenderer` as a plain 8-bit sRGB bitmap, for comparing with a
/// reference. Returns nil only when every attempt gives no picture at all.
///
/// Two things go wrong on iOS 27.0 CI, and this handles both.
///
/// - `LookBundleSnapshotTests.piecesIPad` sometimes failed with "Newly-taken snapshot's data could
///   not be loaded": swift-snapshot-testing turns the new image into PNG data before comparing it
///   pixel by pixel, and that step failed for the renderer's own image (PR #59, Phase 20a). A bitmap
///   made here always encodes, and its pixels are the renderer's. Shared here since Phase 21b, when
///   `ComponentSnapshotTests.iPad` hit the same failure.
/// - `segmented-ipad` came out fully transparent, at the right size, in PR #65's CI run. The log had
///   "building pipeline plane_color took 1.1 seconds" and then "image provider timed out while
///   waiting for phase 6" just before it: on a cold runner the renderer's first shadow or blur
///   waits on a GPU pipeline that is slow to build, gives up, and returns nothing drawn. Every page
///   here has an opaque background, so a picture with no visible pixel is always that failure. It
///   never happens on a dev Mac, where the pipelines are already cached.
///
/// A renderer keeps its first picture (reading `cgImage` again returns the same object and doesn't
/// draw again), so the retry has to use a new renderer. By then the pipeline is built, so the next
/// picture is a real one. Only a failing run gets slower, by half a second per retry.
///
/// A page that really draws nothing still fails: every attempt is empty, and the last one goes to
/// the comparison, which reports the difference.
@MainActor
public func stillImage<Content: View>(
    of content: Content, scale: CGFloat, proposedSize: ProposedViewSize, attempts: Int = 4
) -> UIImage? {
    firstDrawnImage(attempts: attempts) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = proposedSize
        return bitmap(from: renderer.cgImage, scale: scale)
    }
}

/// The first picture from `render` that has something drawn in it, or the last result if none does.
/// Between attempts the main run loop runs for `pause` seconds, so work the renderer waits on can
/// finish.
@MainActor
public func firstDrawnImage(
    attempts: Int, pause: TimeInterval = 0.5, render: () -> UIImage?
) -> UIImage? {
    var image = render()
    var remaining = attempts - 1
    while remaining > 0, image?.hasVisiblePixel != true {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: pause))
        image = render()
        remaining -= 1
    }
    return image
}

/// `image` redrawn as a plain 8-bit sRGB bitmap.
private func bitmap(from image: CGImage?, scale: CGFloat) -> UIImage? {
    guard let image, let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage().map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
}

extension UIImage {
    /// Whether any pixel isn't fully transparent. An image with no pixels counts as having none.
    ///
    /// Redraws the picture as 8-bit RGBA first, so it reads the same whatever format the image
    /// came in.
    public var hasVisiblePixel: Bool {
        guard let image = cgImage, image.width > 0, image.height > 0,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for offset in stride(from: 3, to: image.width * image.height * 4, by: 4) where pixels[offset] != 0 {
            return true
        }
        return false
    }
}
