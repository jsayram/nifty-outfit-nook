import SwiftUI

/// Lays views out left to right, starting a new line when the next one doesn't fit, like words
/// in a paragraph. Chips use it at large text sizes. A view wider than the line gets the whole
/// line and wraps its own text.
public struct NookFlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = NookSpacing.chipGap, lineSpacing: CGFloat = NookSpacing.small) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (line.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    struct Line {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Splits the subviews into lines no wider than `maxWidth`.
    func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        arrange(
            sizes: subviews.map { $0.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) }, maxWidth: maxWidth)
    }

    /// The line-breaking rule on its own, so it can be tested without views.
    func arrange(sizes: [CGSize], maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for (index, proposed) in sizes.enumerated() {
            let size = CGSize(width: min(proposed.width, maxWidth), height: proposed.height)
            let neededWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty && neededWidth > maxWidth {
                lines.append(current)
                current = Line()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append((index, size))
        }
        if !current.items.isEmpty {
            lines.append(current)
        }
        return lines
    }
}
