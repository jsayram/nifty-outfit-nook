import SwiftUI

/// Every layout choice that depends on the window's size, in one place (Phase 15a).
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

    // MARK: Closet

    /// Below this width a window is too narrow for the grid and a piece's detail side by side.
    static let closetDetailMinimumWidth: CGFloat = 760
    /// From this width the filters move into a sidebar of their own.
    static let closetSidebarMinimumWidth: CGFloat = 1080

    /// How Closet lays out in a window `width` points wide.
    static func closet(
        width: CGFloat, horizontalSizeClass: UserInterfaceSizeClass?, dynamicTypeSize: DynamicTypeSize
    ) -> ClosetLayout {
        // At the accessibility sizes the columns would be too narrow for the words, so Closet
        // keeps the one-column page, which already wraps and folds its filters for them.
        guard horizontalSizeClass == .regular, !dynamicTypeSize.isAccessibilitySize else { return .stack }
        if width >= closetSidebarMinimumWidth { return .sidebar }
        if width >= closetDetailMinimumWidth { return .pageAndDetail }
        return .stack
    }

    /// The detail column beside Closet's grid: about a third of the window, 340 to 420 points.
    static func closetDetailWidth(for width: CGFloat) -> CGFloat {
        min(420, max(340, (width * 0.32).rounded()))
    }

    /// Closet's sidebar: about a quarter of the window, 280 to 340 points.
    static func closetSidebarWidth(for width: CGFloat) -> CGFloat {
        min(340, max(280, (width * 0.24).rounded()))
    }
}

/// Closet's three layouts (Phase 15a, `ipad-closet.html`).
nonisolated enum ClosetLayout: String, CaseIterable, Hashable, Sendable {
    /// One column, as on a phone: the page, and a piece's detail pushed over it.
    case stack
    /// The page in one column with the selected piece's detail beside it (an upright iPad).
    case pageAndDetail
    /// Three columns: a sidebar with the header, search, filters, Suitcases and Laundry; the
    /// grid; and the selected piece's detail (an iPad held sideways).
    case sidebar

    /// True when a piece opens beside the grid rather than over it.
    var showsDetailBeside: Bool { self != .stack }
}
