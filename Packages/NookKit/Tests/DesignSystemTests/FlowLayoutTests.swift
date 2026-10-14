import CoreGraphics
import Testing

@testable import DesignSystem

@MainActor
struct FlowLayoutTests {
    private let layout = NookFlowLayout(spacing: 8, lineSpacing: 4)

    private func widths(_ lines: [NookFlowLayout.Line]) -> [[CGFloat]] {
        lines.map { $0.items.map(\.size.width) }
    }

    @Test func keepsItemsOnOneLineWhileTheyFit() {
        let sizes = [CGSize(width: 50, height: 36), CGSize(width: 60, height: 36), CGSize(width: 70, height: 36)]
        let lines = layout.arrange(sizes: sizes, maxWidth: 196)
        #expect(widths(lines) == [[50, 60, 70]])
        #expect(lines[0].width == 196)
    }

    @Test func startsANewLineWhenTheNextItemDoesNotFit() {
        let sizes = [CGSize(width: 50, height: 36), CGSize(width: 60, height: 40), CGSize(width: 70, height: 36)]
        let lines = layout.arrange(sizes: sizes, maxWidth: 195)
        #expect(widths(lines) == [[50, 60], [70]])
        #expect(lines[0].height == 40)
    }

    @Test func anItemWiderThanTheLineGetsTheWholeLine() {
        let sizes = [CGSize(width: 30, height: 36), CGSize(width: 500, height: 80), CGSize(width: 30, height: 36)]
        let lines = layout.arrange(sizes: sizes, maxWidth: 200)
        #expect(widths(lines) == [[30], [200], [30]])
    }

    @Test func nothingToArrange() {
        #expect(layout.arrange(sizes: [], maxWidth: 200).isEmpty)
    }
}
