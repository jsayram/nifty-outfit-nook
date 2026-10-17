import DesignSystem
import SwiftUI

/// The Suitcases and Laundry entries under the filters (RD-13, `.tiles` in `closet.html`): soft
/// tiles with a small drawing, a title and a line. Laundry shows only while tracking is on
/// (RD-11.1). Side by side when each tile's words fit on their lines in half the width, one
/// above the other otherwise: at the accessibility text sizes, and on a 375 point iPhone SE,
/// where "Suitcases" broke as "Suitcas-es" (QA, October 2026).
struct ClosetTiles: View {
    let suitcaseCount: Int
    let tracksLaundry: Bool
    let dirtyCount: Int
    /// One above the other at any text size (iPad's narrow sidebar, Phase 15a).
    var isStacked = false
    let open: (ClosetDestination) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if isStacked {
            VStack(spacing: NookSpacing.small) { tiles }
        } else {
            ClosetTilesLayout(
                spacing: NookSpacing.medium, alwaysStacks: dynamicTypeSize.isAccessibilitySize
            ) { tiles }
        }
    }

    @ViewBuilder private var tiles: some View {
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
                .frame(maxWidth: .infinity, alignment: .leading)
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

/// The tiles side by side, sharing the width equally, while every tile fits its half with its
/// words unwrapped; otherwise one above the other at full width.
struct ClosetTilesLayout: Layout {
    var spacing: CGFloat
    var alwaysStacks = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if let width = sideBySideWidth(proposal.width, subviews) {
            let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max()
            let total = proposal.width ?? (width * CGFloat(subviews.count) + gaps(subviews))
            return CGSize(width: total, height: height ?? 0)
        }
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + gaps(subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if let width = sideBySideWidth(bounds.width, subviews) {
            var x = bounds.minX
            for subview in subviews {
                let size = ProposedViewSize(width: width, height: bounds.height)
                // Centred vertically, as an HStack would.
                let height = subview.sizeThatFits(size).height
                subview.place(at: CGPoint(x: x, y: bounds.midY - height / 2), proposal: size)
                x += width + spacing
            }
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let size = ProposedViewSize(width: bounds.width, height: nil)
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: size)
            y += subview.sizeThatFits(size).height + spacing
        }
    }

    /// Each tile's width side by side, or `nil` when they stack. With no width offered, the
    /// widest tile's own width.
    private func sideBySideWidth(_ width: CGFloat?, _ subviews: Subviews) -> CGFloat? {
        guard !alwaysStacks, !subviews.isEmpty else { return nil }
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        guard let width else { return widest }
        let share = (width - gaps(subviews)) / CGFloat(subviews.count)
        return widest <= share ? share : nil
    }

    private func gaps(_ subviews: Subviews) -> CGFloat {
        spacing * CGFloat(max(0, subviews.count - 1))
    }
}

/// A soft dim while pressed, for tiles and garments that have no button chrome of their own.
struct ClosetPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
