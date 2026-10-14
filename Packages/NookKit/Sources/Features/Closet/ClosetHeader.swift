import DesignSystem
import SwiftUI

/// The top of Closet (RD-13, `closet.html`): the wall with the title and the piece count, and a
/// small open armoire on the right that only says where you are. The armoire is decoration: not
/// tappable, hidden from VoiceOver, and it never stretches. A floor line runs under it.
struct ClosetHeader: View {
    /// "Main closet" and the count under the title.
    let countText: String
    /// The empty closet's armoire has nothing hanging in it (`.is-empty` in the mockup).
    let showsClothes: Bool

    /// The armoire as the mockup scales it: 390 x 284 at 0.535.
    static let armoireSize = CGSize(width: 209, height: 152)

    var body: some View {
        // Title beside the armoire while it fits, as in the mockup. At large text sizes the
        // armoire goes above the title, a little smaller, so the words get the full width.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: NookSpacing.small) {
                titles
                    .fixedSize()
                    .padding(.bottom, NookSpacing.large)
                Spacer(minLength: 0)
                armoire(scale: 1)
            }
            VStack(alignment: .trailing, spacing: NookSpacing.small) {
                armoire(scale: 0.8)
                titles
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, NookSpacing.large)
            }
        }
        .padding(.leading, NookSpacing.xLarge)
        .padding(.trailing, NookSpacing.medium)
        .frame(maxWidth: .infinity)
        .background(Color.nook.wallGradient)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.nook.floorLine)
                .frame(height: 2)
                .offset(y: 2)
                .accessibilityHidden(true)
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Closet", bundle: .module, comment: "Closet's title")
                .nookTextStyle(.display)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                Text("Main closet", bundle: .module, comment: "Under Closet's title: which closet this is")
                Text(countText)
            }
            .nookTextStyle(.label)
            .fontWeight(.semibold)
            .foregroundStyle(.nook.textSecondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("closet.count")
        }
    }

    private func armoire(scale: CGFloat) -> some View {
        ZStack {
            RoomArtImage(.closetArmoire)
            if showsClothes {
                RoomArtImage(.closetArmoireClothes)
            }
        }
        .frame(width: Self.armoireSize.width * scale, height: Self.armoireSize.height * scale)
        .accessibilityHidden(true)
    }
}
