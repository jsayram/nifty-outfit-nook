import DesignSystem
import SwiftUI

/// The top of Suitcases, a suitcase and Laundry (Phase 13), like Closet's: the title in the
/// display style on the wall, a line or two under it, and a drawing on the right that only says
/// where you are. A floor line runs along the bottom when the drawing stands on it.
///
/// At large text sizes the drawing goes above the words, a little smaller, so the title keeps the
/// full width.
struct WallHeader<Art: View>: View {
    let title: String
    /// Under the title, such as "5 pieces · Used today".
    var detail: String?
    var detailIdentifier: String?
    /// True when the drawing stands on the floor, so the wall ends in a floor line under it.
    var hasFloorLine = true
    /// False when the page draws the wall behind more than the header.
    var hasBackground = true
    @ViewBuilder let art: Art

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: NookSpacing.small) {
                titles
                    .fixedSize()
                    .padding(.bottom, NookSpacing.large)
                Spacer(minLength: 0)
                art
            }
            VStack(alignment: .trailing, spacing: NookSpacing.small) {
                art
                    .scaleEffect(0.8, anchor: .bottomTrailing)
                titles
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, NookSpacing.large)
            }
        }
        .padding(.leading, NookSpacing.xLarge)
        .padding(.trailing, NookSpacing.medium)
        .frame(maxWidth: .infinity)
        .background {
            if hasBackground { Color.nook.wallGradient }
        }
        .overlay(alignment: .bottom) {
            if hasFloorLine {
                Rectangle()
                    .fill(Color.nook.floorLine)
                    .frame(height: 2)
                    .offset(y: 2)
                    .accessibilityHidden(true)
            }
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .nookTextStyle(.display)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .nookTextStyle(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(.nook.textSecondary)
                    .accessibilityIdentifier(detailIdentifier ?? "")
            }
        }
    }
}

/// The floor under a header: the floor colour behind the page's lower part, as on Closet.
struct FloorBackground: View {
    var wallHeight: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            Color.nook.background.frame(height: wallHeight)
            Color.nook.floor
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// A group of rows or words on the floor sits on a soft tint, since secondary text on the
    /// bare floor is just under 4.5:1 (DesignSystem README, "Contrast").
    func floorCard() -> some View {
        background {
            NookRadius.shape(NookRadius.tile)
                .fill(Color.nook.tint)
        }
    }
}
