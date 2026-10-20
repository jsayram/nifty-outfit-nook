import CoreGraphics
import SwiftUI
import UIKit

/// The renderer's picture redrawn as a plain 8-bit sRGB bitmap, for comparing with a reference.
///
/// On iOS 27.0 CI, `LookBundleSnapshotTests.piecesIPad` sometimes failed with "Newly-taken
/// snapshot's data could not be loaded": swift-snapshot-testing turns the new image into PNG
/// data before comparing it pixel by pixel, and that step failed for the renderer's own image
/// (PR #59, Phase 20a). A bitmap made here always encodes, and its pixels are the renderer's.
@MainActor
func stillImage<Content: View>(from renderer: ImageRenderer<Content>, scale: CGFloat) -> UIImage? {
    guard let image = renderer.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage().map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
}
