import DesignSystem
import SwiftUI

/// Which part of a browsing page a view draws: the whole page in one column, or one of the two
/// columns it splits into when the filters move into a sidebar (`BrowseLayout.sidebar`).
enum BrowsePart {
    /// The whole page in one column (a phone, an upright iPad).
    case whole
    /// The header, search and filters, and anything else that isn't the grid.
    case sidebar
    /// The grid, or the loading, error, empty or no-match state that stands in for it.
    case grid
}

/// The columns of a screen with a grid and a detail, for a layout (Closet in Phase 15a, Saved
/// Looks in 15b): the page alone, the page with the detail beside it, or the sidebar, the grid
/// and the detail. Separate from the screens so snapshot tests can draw each layout from a model.
///
/// These are plain columns, not a `NavigationSplitView`: each screen keeps one navigation stack
/// that other tabs can push onto, and the tab view's width class is overridden (`docs/ipad.md`).
struct BrowseColumns<Page: View, Detail: View>: View {
    let layout: BrowseLayout
    /// The window's width, which sets the columns' widths.
    let width: CGFloat
    /// Starts the columns' accessibility identifiers: `closet.sidebar`, `savedLooks.detail`.
    let identifier: String
    let page: (BrowsePart) -> Page
    @ViewBuilder let detail: Detail

    var body: some View {
        switch layout {
        case .stack:
            page(.whole)
        case .pageAndDetail:
            HStack(alignment: .top, spacing: 0) {
                page(.whole)
                detailColumn
            }
        case .sidebar:
            HStack(alignment: .top, spacing: 0) {
                page(.sidebar)
                    .frame(width: WindowLayout.browseSidebarWidth(for: width))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("\(identifier).sidebar")
                page(.grid)
                detailColumn
            }
        }
    }

    private var detailColumn: some View {
        detail
            .frame(width: WindowLayout.browseDetailWidth(for: width))
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(identifier).detail")
    }
}

/// Beside the grid before she picks something: what will show there.
struct BrowseDetailPlaceholder: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        NookEmptyState(title, message: message, systemImage: systemImage)
            .padding(.horizontal, NookSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.nook.wallGradient.ignoresSafeArea())
    }
}

extension View {
    /// A pushed screen whose title is big on the page: the bar keeps the title for Back and
    /// VoiceOver but shows none of its own. Beside a grid (`isPushed` false) the screen has no
    /// bar, so it sets nothing and leaves the grid's bar alone.
    func pagedTitle(_ title: String, isPushed: Bool = true) -> some View {
        modifier(PagedTitle(title: title, isPushed: isPushed))
    }
}

private struct PagedTitle: ViewModifier {
    let title: String
    let isPushed: Bool

    func body(content: Content) -> some View {
        if isPushed {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(verbatim: "").accessibilityHidden(true)
                    }
                }
        } else {
            content
        }
    }
}
