import DesignSystem
import SwiftUI

/// The Suitcases and Laundry entries under the filters (RD-13, `.tiles` in `closet.html`): soft
/// tiles with a small drawing, a title and a line. Laundry shows only while tracking is on
/// (RD-11.1). Side by side normally, stacked at the accessibility text sizes.
struct ClosetTiles: View {
    let suitcaseCount: Int
    let tracksLaundry: Bool
    let dirtyCount: Int
    let open: (ClosetDestination) -> Void

    var body: some View {
        NookAdaptiveStack(spacing: NookSpacing.medium) {
            ClosetTile(
                art: .closetSuitcase,
                title: String(localized: "Suitcases", bundle: .module, comment: "Closet tile"),
                detail: String(
                    localized: "\(suitcaseCount) suitcases", bundle: .module,
                    comment: "Closet tile: how many suitcases she has"),
                identifier: "closet.suitcases"
            ) {
                open(.suitcases)
            }
            if tracksLaundry {
                ClosetTile(
                    art: dirtyCount > 0 ? .closetBasket : .closetBasketEmpty,
                    title: String(localized: "Laundry", bundle: .module, comment: "Closet tile"),
                    detail: dirtyCount > 0
                        ? String(
                            localized: "\(dirtyCount) to wash", bundle: .module,
                            comment: "Hamper plate: how many pieces are dirty")
                        : String(localized: "All clean", bundle: .module, comment: "Hamper plate: nothing to wash"),
                    identifier: "closet.laundry"
                ) {
                    open(.laundry)
                }
            }
        }
    }
}

/// One tile: a 50 point drawing, a title and a line on a soft tint with a shadow below, and a
/// chevron. One VoiceOver button that reads its words.
private struct ClosetTile: View {
    let art: RoomArt
    let title: String
    let detail: String
    let identifier: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 60

    var body: some View {
        Button(action: action) {
            HStack(spacing: NookSpacing.small) {
                RoomArtImage(art)
                    .frame(width: 48, height: 44)
                    .frame(width: 50, height: 50)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.textPrimary)
                    Text(detail)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Font.nook.label)
                    .foregroundStyle(.nook.chevron)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 5)
            .padding(.trailing, NookSpacing.medium)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: max(minHeight, NookSpacing.minimumTapTarget))
            .background {
                NookRadius.shape(NookRadius.tile)
                    .fill(Color.nook.tint)
                    .softShadow(.drop, in: NookRadius.shape(NookRadius.tile))
            }
            .contentShape(NookRadius.shape(NookRadius.tile))
        }
        .buttonStyle(ClosetPressStyle())
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(detail))
        .accessibilityIdentifier(identifier)
    }
}

/// A soft dim while pressed, for tiles and garments that have no button chrome of their own.
struct ClosetPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
