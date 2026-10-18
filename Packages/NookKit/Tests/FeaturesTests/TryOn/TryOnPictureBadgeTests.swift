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

    /// Over a person the badge never covers her: it sits in the bottom corner, on the floor, and
    /// only on a picture wide enough to keep it off her feet (real-photo audit, 17 October 2026).
    /// A drawn picture keeps it in the top corner, over empty space.
    @Test func theBadgeKeepsOffAPerson() {
        #expect(TryOnPictureView.badgeAlignment(showsPerson: true) == .bottomLeading)
        #expect(TryOnPictureView.badgeAlignment(showsPerson: false) == .topLeading)
        // Picture detail is wide enough; a grid tile and the Try it on sheet's preview aren't, and
        // say Simulated in their words instead.
        #expect(TryOnPictureView.showsBadge(width: PictureDetailPage.pictureWidth, showsPerson: true))
        #expect(!TryOnPictureView.showsBadge(width: 200, showsPerson: true))
        #expect(TryOnPictureView.showsBadge(width: 200, showsPerson: false))
        #expect(!TryOnPictureView.showsBadge(width: 104, showsPerson: false))
    }
}
