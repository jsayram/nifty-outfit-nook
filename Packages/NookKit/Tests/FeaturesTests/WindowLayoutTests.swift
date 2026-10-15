import SwiftUI
import Testing

@testable import Features

/// The layout choices that depend on the window (Phase 15a). Widths are the windows measured on
/// the iOS 26.5 simulator: full screen on the 11- and 13-inch iPads, and windows dragged to
/// about two thirds, a half and a third of the 11-inch screen held sideways (795, 618 and
/// 416 points; the last two were compact width there).
struct WindowLayoutTests {
    @Test(
        arguments: [
            (1376, BrowseLayout.sidebar),  // 13-inch, sideways
            (1210, .sidebar),  // 11-inch, sideways
            (1133, .sidebar),  // iPad mini, sideways
            (1032, .pageAndDetail),  // 13-inch, upright
            (834, .pageAndDetail),  // 11-inch, upright
            (795, .pageAndDetail),  // two thirds of the 11-inch held sideways
            (744, .stack),  // iPad mini, upright: too narrow for the detail beside the grid
        ] as [(CGFloat, BrowseLayout)])
    func closetFollowsTheWidth(width: CGFloat, expected: BrowseLayout) {
        let layout = WindowLayout.browse(width: width, horizontalSizeClass: .regular, dynamicTypeSize: .large)
        #expect(layout == expected, "\(width) points")
    }

    /// Compact width is a phone layout, however wide the window says it is.
    @Test(arguments: [320, 416, 618, 1210] as [CGFloat])
    func compactWidthGetsThePhonePage(width: CGFloat) {
        #expect(WindowLayout.browse(width: width, horizontalSizeClass: .compact, dynamicTypeSize: .large) == .stack)
        #expect(WindowLayout.browse(width: width, horizontalSizeClass: nil, dynamicTypeSize: .large) == .stack)
    }

    /// At the accessibility sizes the columns would squeeze the words, so it's the page.
    @Test(arguments: DynamicTypeSize.allCases)
    func accessibilitySizesGetThePhonePage(size: DynamicTypeSize) {
        let layout = WindowLayout.browse(width: 1376, horizontalSizeClass: .regular, dynamicTypeSize: size)
        #expect((layout == .stack) == size.isAccessibilitySize)
    }

    /// The columns leave the grid room for at least three pieces across.
    @Test(arguments: [1133, 1210, 1376, 760, 834, 1032] as [CGFloat])
    func gridKeepsThreeColumns(width: CGFloat) {
        let layout = WindowLayout.browse(width: width, horizontalSizeClass: .regular, dynamicTypeSize: .large)
        var grid = width - WindowLayout.browseDetailWidth(for: width)
        if layout == .sidebar {
            grid -= WindowLayout.browseSidebarWidth(for: width)
        }
        let columns = Int((grid - 2 * 16 + 8) / (104 + 8))
        #expect(columns >= 3, "\(width) points leaves \(grid) for the grid")
    }

    @Test func detailAndSidebarWidthsStayInTheirRange() {
        for width in stride(from: 600, through: 1600, by: 50) {
            let detail = WindowLayout.browseDetailWidth(for: CGFloat(width))
            let sidebar = WindowLayout.browseSidebarWidth(for: CGFloat(width))
            #expect((340...420).contains(detail))
            #expect((280...340).contains(sidebar))
        }
    }

    @Test func onlyThePhonePageOpensAPieceOverTheGrid() {
        #expect(!BrowseLayout.stack.showsDetailBeside)
        #expect(BrowseLayout.pageAndDetail.showsDetailBeside)
        #expect(BrowseLayout.sidebar.showsDetailBeside)
    }

    // MARK: Panes (Phase 15b)

    /// Content widths: the 11-inch iPad sideways and upright, two thirds of it sideways, the
    /// 13-inch upright and the iPad mini upright, each less 16-point margins.
    @Test(
        arguments: [
            (1178, true, true),  // 11-inch, sideways
            (802, true, false),  // 11-inch, upright: the look beside its pieces, the rows in one column
            (763, true, false),  // two thirds of the 11-inch held sideways
            (1000, true, true),  // 13-inch, upright
            (712, false, false),  // iPad mini, upright
        ] as [(CGFloat, Bool, Bool)])
    func panesFollowTheWidth(width: CGFloat, look: Bool, rows: Bool) {
        #expect(
            WindowLayout.showsPanesSideBySide(width: width, horizontalSizeClass: .regular, dynamicTypeSize: .large)
                == look, "\(width) points")
        #expect((width >= WindowLayout.rowPanesMinimumWidth) == rows, "\(width) points")
    }

    /// Compact windows and the accessibility sizes keep one column, however wide.
    @Test(arguments: DynamicTypeSize.allCases)
    func panesNeedARegularWindowAndANonAccessibilitySize(size: DynamicTypeSize) {
        #expect(
            WindowLayout.showsPanesSideBySide(width: 1178, horizontalSizeClass: .regular, dynamicTypeSize: size)
                == !size.isAccessibilitySize)
        #expect(!WindowLayout.showsPanesSideBySide(width: 1178, horizontalSizeClass: .compact, dynamicTypeSize: size))
        #expect(!WindowLayout.showsPanesSideBySide(width: 1178, horizontalSizeClass: nil, dynamicTypeSize: size))
    }

    /// Side by side, the look beside its pieces gets at least the 300 points it has on a phone.
    @MainActor
    @Test func eachPaneHasRoomForALook() {
        let pane = (WindowLayout.panesMinimumWidth - WindowLayout.panesGap) / 2
        #expect(pane >= LookBundleSize.large.width)
        #expect(WindowLayout.readableWidth < WindowLayout.panesMaximumWidth)
    }
}
