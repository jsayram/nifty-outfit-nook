import SwiftUI

/// Every layout choice that depends on the window's size, in one place (Phases 15a and 15b).
///
/// Screens decide from the window they're actually in: its width and height, its size classes
/// and the text size. Never from the device. An iPad app in a narrow Split View, Slide Over or
/// Stage Manager window gets the phone layouts, and a wide window gets the iPad ones, whatever
/// the hardware. `docs/ipad.md` has the sizes each choice was checked at.
nonisolated enum WindowLayout {
    // MARK: Home

    /// Which arrangement of the room a window gets, scaled and placed for it.
    ///
    /// A compact-width window always gets the phone room. A regular-width window gets the iPad
    /// room that suits its shape: the wide room when it's wider than tall, the tall room when
    /// it's upright. Either is used only when every control keeps a 44 pt target without
    /// scrolling; otherwise the other is tried, then the phone room, which may scroll.
    ///
    /// - Parameters:
    ///   - size: the whole area the room draws in, including what sits under the bars.
    ///   - insets: the bars' heights.
    ///   - horizontalSizeClass: the window's width class.
    static func room(size: CGSize, insets: EdgeInsets, horizontalSizeClass: UserInterfaceSizeClass?) -> RoomLayout {
        guard horizontalSizeClass == .regular else {
            return RoomLayout(plan: .upright, size: size, insets: insets)
        }
        let order: [RoomPlan] = size.width > size.height ? [.wide, .tall] : [.tall, .wide]
        for plan in order {
            let layout = RoomLayout(plan: plan, size: size, insets: insets)
            if layout.fitsWithFullTargets { return layout }
        }
        return RoomLayout(plan: .upright, size: size, insets: insets)
    }

    // MARK: Closet and Saved Looks

    /// Below this width a window is too narrow for a grid and the detail beside it.
    static let browseDetailMinimumWidth: CGFloat = 760
    /// From this width the search and filters move into a sidebar of their own.
    static let browseSidebarMinimumWidth: CGFloat = 1080

    /// How a screen with a grid and a detail lays out in a window `width` points wide: Closet
    /// (Phase 15a) and Saved Looks (Phase 15b).
    static func browse(
        width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?, dynamicTypeSize: DynamicTypeSize
    ) -> BrowseLayout {
        // At the accessibility sizes the columns would be too narrow for the words, so the
        // screen keeps the one-column page, which already wraps and folds its filters for them.
        guard horizontalSizeClass == .regular, !dynamicTypeSize.isAccessibilitySize else { return .stack }
        if width >= browseSidebarMinimumWidth { return .sidebar }
        if width >= browseDetailMinimumWidth { return .pageAndDetail }
        return .stack
    }

    /// The detail column beside a grid: about a third of the window, 340 to 420 points.
    static func browseDetailWidth(for width: CGFloat) -> CGFloat {
        min(420, max(340, (width * 0.32).rounded()))
    }

    /// The sidebar: about a quarter of the window, 280 to 340 points.
    static func browseSidebarWidth(for width: CGFloat) -> CGFloat {
        min(340, max(280, (width * 0.24).rounded()))
    }

    // MARK: Pages (Phase 15b)

    /// The widest a column of words, rows or form fields gets. Wider windows keep it in the
    /// middle, so nothing stretches from edge to edge (`View.readablePane()`).
    static let readableWidth: CGFloat = 640

    /// The narrowest content that two panes side by side fit in: a 300-point look and its
    /// pieces or buttons beside it. An upright 11-inch iPad (834 points less its margins) has
    /// room; the iPad mini upright (744) and every compact window don't.
    static let panesMinimumWidth: CGFloat = 720

    /// Rows with a title, a line and a value beside them need more: two columns of rows only
    /// from an iPad held sideways (or the 13-inch upright). Upright on the 11-inch they stay in
    /// one readable column.
    static let rowPanesMinimumWidth: CGFloat = 960

    /// The widest two panes side by side get, together, as in the mockups' tablet layout.
    static let panesMaximumWidth: CGFloat = 1120

    /// The space between two panes side by side.
    static let panesGap: CGFloat = 40

    /// Whether a window may show two panes side by side at all: never in a compact window, and
    /// never at the accessibility sizes, where a half-width column would squeeze the words.
    static func allowsPanesSideBySide(
        horizontalSizeClass: UserInterfaceSizeClass?, dynamicTypeSize: DynamicTypeSize
    ) -> Bool {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
    }

    /// Whether a page `width` points wide (its content, inside its margins) shows two panes
    /// side by side (`WidePanes`), or one above the other as on a phone.
    static func showsPanesSideBySide(
        width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?, dynamicTypeSize: DynamicTypeSize
    ) -> Bool {
        allowsPanesSideBySide(horizontalSizeClass: horizontalSizeClass, dynamicTypeSize: dynamicTypeSize)
            && width >= panesMinimumWidth
    }
}

/// The three layouts of a screen with a grid and a detail: Closet (Phase 15a,
/// `ipad-closet.html`) and Saved Looks (Phase 15b, `ipad-saved.html`).
nonisolated enum BrowseLayout: String, CaseIterable, Hashable, Sendable {
    /// One column, as on a phone: the page, and the detail pushed over it.
    case stack
    /// The page in one column with the selected item's detail beside it (an upright iPad).
    case pageAndDetail
    /// Three columns: a sidebar with the header, search and filters; the grid; and the
    /// selected item's detail (an iPad held sideways).
    case sidebar

    /// True when an item opens beside the grid rather than over it.
    var showsDetailBeside: Bool { self != .stack }
}
