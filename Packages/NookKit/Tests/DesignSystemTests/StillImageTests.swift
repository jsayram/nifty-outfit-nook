import NookTestSupport
import SwiftUI
import Testing
import UIKit

/// The retry in `stillImage`, which CI needs when the renderer comes back with nothing drawn
/// (PR #65). The failure itself only shows on a cold CI runner, so these use a stand-in renderer.
@MainActor
@Suite
struct StillImageTests {
    private func picture(alpha: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            UIColor.red.withAlphaComponent(alpha).setFill()
            context.fill(CGRect(x: 2, y: 2, width: 3, height: 3))
        }
    }

    @Test func aTransparentPictureHasNoVisiblePixel() {
        #expect(!picture(alpha: 0).hasVisiblePixel)
        #expect(picture(alpha: 1).hasVisiblePixel)
        #expect(picture(alpha: 0.2).hasVisiblePixel)
    }

    @Test func anEmptyPictureIsRenderedAgainUntilItHasPixels() {
        var calls = 0
        let image = firstDrawnImage(attempts: 4, pause: 0) {
            calls += 1
            return picture(alpha: calls < 3 ? 0 : 1)
        }
        #expect(calls == 3)
        #expect(image?.hasVisiblePixel == true)
    }

    @Test func aPictureWithPixelsIsNotRenderedTwice() {
        var calls = 0
        _ = firstDrawnImage(attempts: 4, pause: 0) {
            calls += 1
            return picture(alpha: 1)
        }
        #expect(calls == 1)
    }

    @Test func aPageThatNeverDrawsGivesUpAndReturnsTheLastPicture() {
        var calls = 0
        let image = firstDrawnImage(attempts: 3, pause: 0) {
            calls += 1
            return picture(alpha: 0)
        }
        #expect(calls == 3)
        #expect(image != nil)
        #expect(image?.hasVisiblePixel == false)
    }

    @Test func noPictureAtAllIsRenderedAgainToo() {
        var calls = 0
        let image = firstDrawnImage(attempts: 3, pause: 0) {
            calls += 1
            return calls < 2 ? nil : picture(alpha: 1)
        }
        #expect(calls == 2)
        #expect(image != nil)
    }

    @Test func aRealRenderedPageHasPixelsAndIsAnEightBitBitmap() throws {
        let image = try #require(
            stillImage(
                of: Color.red.frame(width: 40, height: 20), scale: 2,
                proposedSize: ProposedViewSize(width: 40, height: nil)))
        #expect(image.hasVisiblePixel)
        #expect(image.cgImage?.bitsPerComponent == 8)
        #expect(image.pngData() != nil)
    }
}
