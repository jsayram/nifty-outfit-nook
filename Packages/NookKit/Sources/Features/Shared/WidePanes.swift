import DesignSystem
import SwiftUI

extension View {
    /// Keeps a page's column to a readable width in the middle of a wide window, so rows, words
    /// and fields never stretch from edge to edge (Phase 15b). A phone is narrower than the
    /// width, so nothing changes there.
    func readablePane(maxWidth: CGFloat = WindowLayout.readableWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// In a regular-width window, a scroll view's content that's shorter than the window sits
    /// in the middle of it, as the mockups centre their tablet panes. Taller content scrolls from
    /// the top as before, and a phone is unchanged.
    func centersShortContentInWideWindows() -> some View {
        modifier(CentersShortContent())
    }
}

private struct CentersShortContent: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content
            .defaultScrollAnchor(horizontalSizeClass == .regular ? .center : nil, for: .alignment)
    }
}

/// Two panes, side by side when the page is wide enough, or one above the other as on a phone
/// (Phase 15b). The mockups' tablet layout does this for results, Style Me and the other pages
/// that have a picture and its controls: the look on the left and what she can do with it on
/// the right.
///
/// Side by side needs a regular-width window, a text size below the accessibility sizes, and
/// `minimumWidth` for the page's content (`WindowLayout.panesMinimumWidth` unless the page needs
/// more); the two panes then share at most `WindowLayout.panesMaximumWidth`, centred. Otherwise
/// the panes stack in one column at the readable width, exactly as the page was before: the same
/// views with the same spacing.
///
/// Each pane's content is told which arrangement it's in, so a picture can grow beside its
/// controls. The choice is made from the space the page is offered (`ViewThatFits`), so it's
/// the same in a still image as on screen.
struct WidePanes<Leading: View, Trailing: View>: View {
    /// Between the views in each pane, and between the panes when they stack.
    var spacing: CGFloat
    /// How each pane lines up its views.
    var alignment: HorizontalAlignment = .center
    /// Where the shorter pane sits beside the taller one.
    var verticalAlignment: VerticalAlignment = .center
    /// The leading pane's share of the width, side by side.
    var leadingShare: CGFloat = 0.5
    /// The narrowest content the panes go side by side in.
    var minimumWidth = WindowLayout.panesMinimumWidth
    @ViewBuilder let leading: (_ isSideBySide: Bool) -> Leading
    @ViewBuilder let trailing: (_ isSideBySide: Bool) -> Trailing

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var mayGoSideBySide: Bool {
        WindowLayout.allowsPanesSideBySide(horizontalSizeClass: horizontalSizeClass, dynamicTypeSize: dynamicTypeSize)
    }

    var body: some View {
        if mayGoSideBySide {
            ViewThatFits(in: .horizontal) {
                sideBySide
                    .frame(minWidth: minimumWidth, idealWidth: minimumWidth, maxWidth: WindowLayout.panesMaximumWidth)
                    .frame(maxWidth: .infinity)
                stacked
            }
        } else {
            stacked
        }
    }

    private var stacked: some View {
        VStack(alignment: alignment, spacing: spacing) {
            leading(false)
            trailing(false)
        }
        .readablePane()
    }

    private var sideBySide: some View {
        PaneColumns(leadingShare: leadingShare, gap: WindowLayout.panesGap, alignment: verticalAlignment) {
            VStack(alignment: alignment, spacing: spacing) { leading(true) }
            VStack(alignment: alignment, spacing: spacing) { trailing(true) }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Two columns: the first takes `leadingShare` of the width less the gap, the second the rest,
/// and the shorter one lines up with the taller one by `alignment`.
private struct PaneColumns: Layout {
    let leadingShare: CGFloat
    let gap: CGFloat
    let alignment: VerticalAlignment

    private func widths(for width: CGFloat) -> (CGFloat, CGFloat) {
        let available = max(0, width - gap)
        let leading = (available * leadingShare).rounded()
        return (leading, available - leading)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? WindowLayout.panesMinimumWidth
        let (leading, trailing) = widths(for: width)
        let heights = zip(subviews, [leading, trailing]).map { subview, columnWidth in
            subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (leading, trailing) = widths(for: bounds.width)
        var x = bounds.minX
        for (subview, columnWidth) in zip(subviews, [leading, trailing]) {
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let y: CGFloat =
                switch alignment {
                case .top: bounds.minY
                case .bottom: bounds.maxY - size.height
                default: bounds.minY + (bounds.height - size.height) / 2
                }
            subview.place(
                at: CGPoint(x: x, y: y), anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: size.height))
            x += columnWidth + gap
        }
    }
}
