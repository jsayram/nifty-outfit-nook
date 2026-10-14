import DesignSystem
import Models
import SwiftUI

/// Closet's content, top to bottom (RD-13): the header with the armoire, the search field, the
/// filter rows, Suitcases and Laundry, then the grid of her pieces, and "Recently deleted · N"
/// at the bottom when anything is in it (LR-16). An empty closet explains how to add a piece
/// instead (RD-13.2).
///
/// Separate from `ClosetScreen` so snapshot tests can draw it from a model without navigation.
struct ClosetPage: View {
    @Bindable var model: ClosetModel
    let open: (ClosetDestination) -> Void
    let retry: () -> Void

    @Environment(\.closetIsStillImage) private var isStillImage

    /// Past this the controls read badly; the grid keeps the full width (iPad's own layout is 15a).
    static let controlsMaximumWidth: CGFloat = 640

    var body: some View {
        if isStillImage {
            page
        } else {
            ScrollView(.vertical) {
                page
            }
            .scrollDismissesKeyboard(.immediately)
            .background {
                // The wall runs up under the navigation bar; the floor carries on below.
                VStack(spacing: 0) {
                    Color.nook.background.frame(height: 400)
                    Color.nook.floor
                }
                .ignoresSafeArea()
            }
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            ClosetHeader(countText: model.countText, showsClothes: !model.isEmpty && model.phase == .loaded)
            floor
                .padding(.top, NookSpacing.medium)
                .padding(.bottom, NookSpacing.xxxLarge)
                .frame(maxWidth: .infinity, alignment: .top)
                .background(Color.nook.floor)
        }
    }

    @ViewBuilder private var floor: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(String(localized: "Opening your closet", bundle: .module, comment: "Closet loading"))
                .stateCard()
        case .failed:
            NookErrorState(
                String(localized: "Your closet didn’t load", bundle: .module, comment: "Closet error title"),
                message: String(
                    localized: "Nothing was lost. Try again in a moment.", bundle: .module,
                    comment: "Closet error message"),
                retry: retry
            )
            .stateCard()
        case .loaded:
            VStack(spacing: 0) {
                if model.isEmpty {
                    emptyCloset
                } else {
                    controls
                    if model.hasNoMatches {
                        noMatches
                    } else {
                        GarmentGrid(items: model.shown, now: model.loadedAt) { item in
                            open(.garment(item.id, name: item.name))
                        }
                        .padding(.horizontal, NookSpacing.screenMargin)
                        .padding(.top, 14)
                    }
                }
                if model.deletedCount > 0 {
                    recentlyDeleted
                        .padding(.top, NookSpacing.xxLarge)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            NookSearchField(
                String(localized: "Search your closet", bundle: .module, comment: "Closet search field prompt"),
                text: $model.searchText,
                onSubmit: model.applySearchNow
            )
            .padding(.horizontal, NookSpacing.screenMargin)
            ClosetFilters(model: model)
                .padding(.top, NookSpacing.small)
            ClosetTiles(
                suitcaseCount: model.suitcases.count, tracksLaundry: model.tracksLaundry,
                dirtyCount: model.dirtyCount, open: open
            )
            .padding(.horizontal, NookSpacing.screenMargin)
            .padding(.top, NookSpacing.small)
        }
        .frame(maxWidth: Self.controlsMaximumWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// No pieces match: says which filters are on, with Clear filters (LR-09.3).
    private var noMatches: some View {
        NookEmptyState(
            String(localized: "No pieces match", bundle: .module, comment: "Closet: nothing matches the filters"),
            message: model.filterSummary,
            systemImage: "magnifyingglass"
        ) {
            NookButton(
                String(
                    localized: "Clear filters", bundle: .module, comment: "Button: clears every filter and the search"),
                systemImage: "xmark", kind: .soft, fillsWidth: true
            ) {
                model.clearFilters()
            }
            .accessibilityIdentifier("closet.noMatches.clear")
        }
        .stateCard()
        .padding(.top, NookSpacing.large)
        .accessibilityIdentifier("closet.noMatches")
    }

    /// RD-13.2: the empty closet says how to add a piece, from a photo or in words.
    private var emptyCloset: some View {
        VStack(spacing: 0) {
            RoomArtImage(.closetEmptyHangers)
                .frame(width: 200, height: 64)
                .accessibilityHidden(true)
            NookEmptyState(
                String(localized: "Your closet is empty", bundle: .module, comment: "Empty closet title"),
                message: String(
                    localized: "Add a piece from a photo, or describe it in words. You can add more whenever you like.",
                    bundle: .module, comment: "Empty closet message"),
                systemImage: "hanger"
            ) {
                NookButton(
                    String(localized: "Add a piece", bundle: .module, comment: "Button: adds a piece from a photo"),
                    systemImage: "plus", fillsWidth: true
                ) {
                    open(.addPiece(.photo))
                }
                .accessibilityIdentifier("closet.empty.addPiece")
                NookButton(
                    String(localized: "Describe in words", bundle: .module, comment: "Button: adds a piece by words"),
                    systemImage: "pencil", kind: .soft, fillsWidth: true
                ) {
                    open(.addPiece(.words))
                }
                .accessibilityIdentifier("closet.empty.describe")
            }
            .stateCard()
        }
        .padding(.top, NookSpacing.large)
    }

    /// "Recently deleted · N" (LR-16).
    private var recentlyDeleted: some View {
        Button {
            open(.recentlyDeleted)
        } label: {
            NookRow(
                String(localized: "Recently deleted", bundle: .module, comment: "Row at the bottom of Closet"),
                value: model.deletedCount.formatted(),
                systemImage: "trash",
                accessory: .chevron
            )
        }
        .buttonStyle(.nookRow)
        // On a tint, like the states: the count is secondary text, which needs it on the floor.
        .background(Color.nook.tint, in: NookRadius.shape(NookRadius.group))
        .padding(.horizontal, NookSpacing.screenMargin)
        .frame(maxWidth: Self.controlsMaximumWidth)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("closet.recentlyDeleted")
    }
}

extension View {
    /// A state's words sit on a soft tint, since secondary text on the bare floor is just under
    /// 4.5:1 (DesignSystem README, "Contrast").
    fileprivate func stateCard() -> some View {
        self
            .background {
                NookRadius.shape(NookRadius.tile)
                    .fill(Color.nook.tint)
            }
            .padding(.horizontal, NookSpacing.screenMargin)
            .frame(maxWidth: 480)
    }
}

extension EnvironmentValues {
    /// True when Closet is drawn to a still image (the snapshot tests): no scroll view, so the
    /// whole page draws. Never set in the app.
    @Entry var closetIsStillImage = false
}
