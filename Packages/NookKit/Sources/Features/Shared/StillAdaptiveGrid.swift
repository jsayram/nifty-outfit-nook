import SwiftUI

/// A plain stand-in for `LazyVGrid` with one adaptive column item, for still images.
///
/// A still image measures a lazy grid from estimates. On the iOS 27.0 simulator the Starting
/// piece sheet's grid sometimes came out 18 points taller than it drew, so the snapshot was 18
/// points taller with the page moved down 9, about half the time (Phase 20a). This lays out the
/// same columns eagerly: as many columns of at least `minimum` as fit, sharing the width, each
/// row as tall as its tallest item, items centred in their cells, as `LazyVGrid` does.
struct StillAdaptiveGrid: Layout {
    var minimum: CGFloat
    var spacing: CGFloat
    var rowSpacing: CGFloat

    private func columns(for width: CGFloat) -> (count: Int, width: CGFloat) {
        let count = max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
        return (count, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
    }

    private func rowHeights(_ subviews: Subviews, columns: (count: Int, width: CGFloat)) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns.count).map { start in
            subviews[start..<min(start + columns.count, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: columns.width, height: nil)).height }
                .max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimum
        let heights = rowHeights(subviews, columns: columns(for: width))
        let height = heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * rowSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = columns(for: bounds.width)
        let heights = rowHeights(subviews, columns: layout)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for column in 0..<layout.count {
                let index = row * layout.count + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (layout.width + spacing)
                subviews[index].place(
                    at: CGPoint(x: x + layout.width / 2, y: y + height / 2), anchor: .center,
                    proposal: ProposedViewSize(width: layout.width, height: height))
            }
            y += height + rowSpacing
        }
    }
}
