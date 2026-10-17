import SwiftUI
import Testing

@testable import DesignSystem
@testable import Features

/// The Simulated badge on a try-on picture. At AX5 on an iPhone 12 (390 points) it grew until
/// "Simulated" broke as "Simu-lated" over two lines and covered the top of the picture (QA, 17
/// October 2026). It's words on art, like the room's plates, so it stops growing at xxxLarge;
/// the page under the picture says the picture is simulated at full size, and VoiceOver reads
/// it with the picture.
@MainActor
struct TryOnPictureBadgeTests {
    /// The room the badge has on picture detail, the largest picture a phone shows.
    private let room =
        PictureDetailPage.pictureWidth - 2 * TryOnPictureView.badgePadding(width: PictureDetailPage.pictureWidth)

    @Test func theBadgeStaysOnOneLineAtTheLargestSize() {
        let natural = fittedWidth(of: TryOnPictureView.badge, width: 10_000, dynamicTypeSize: .accessibility5)
        #expect(natural <= room, "The badge needs \(natural) points at AX5; the picture has \(room)")
        let largest = fittedHeight(of: TryOnPictureView.badge, width: room, dynamicTypeSize: .accessibility5)
        let capped = fittedHeight(of: TryOnPictureView.badge, width: room, dynamicTypeSize: .xxxLarge)
        #expect(largest == capped)
    }

    @Test func theBadgeStillGrowsUpToXXXLarge() {
        let standard = fittedHeight(of: TryOnPictureView.badge, width: room, dynamicTypeSize: .large)
        let capped = fittedHeight(of: TryOnPictureView.badge, width: room, dynamicTypeSize: .xxxLarge)
        #expect(capped > standard)
    }
}
