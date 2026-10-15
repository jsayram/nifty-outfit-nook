import DesignSystem
import Models
import SwiftUI

/// What Saved Looks' buttons do. The screen supplies them.
struct SavedLooksActions {
    var open: (SavedLookItem) -> Void = { _ in }
    /// Undo on the line about a look she just deleted.
    var undoDelete: () -> Void = {}
    var makeYourOwn: () -> Void = {}
    var retry: () -> Void = {}
    /// The Pictures tab (Phase 12b): a picture, and the look a picture came from.
    var openPicture: (SavedPictureItem) -> Void = { _ in }
    var openLook: (Look) -> Void = { _ in }
    /// Undo on the line about a picture she just deleted.
    var undoPictureDelete: () -> Void = {}
}

/// What shows beside the grid in a wide window (Phase 15b): a look's detail or a picture's.
nonisolated enum SavedLooksSelection: Hashable, Sendable {
    case look(Look.ID)
    case picture(TryOnPicture.ID)

    /// The same screen pushed, for a narrow window.
    var destination: SavedLooksDestination {
        switch self {
        case .look(let id): .look(id)
        case .picture(let id): .picture(id)
        }
    }

    var lookID: Look.ID? {
        if case .look(let id) = self { id } else { nil }
    }

    var pictureID: TryOnPicture.ID? {
        if case .picture(let id) = self { id } else { nil }
    }

    /// A pushed look or picture, which a wide window shows beside the grid instead.
    init?(_ destination: SavedLooksDestination) {
        switch destination {
        case .look(let id): self = .look(id)
        case .picture(let id): self = .picture(id)
        case .makeYourOwnLook, .closet: return nil
        }
    }
}

/// Saved Looks' content, top to bottom (`saved.html`, RD-08): the title and count, the Looks and
/// Pictures switch, then the search field, the piece and colour filters (LR-09), the count line
/// with Clear, and the grid of looks or of pictures. An empty Saved Looks explains how to save a
/// look (RD-08.4), and an empty Pictures tab what pictures are and that they need a look; a
/// search with no matches names the filters, with Clear filters (LR-09.3).
///
/// On a wide iPad window (Phase 15b, `ipad-saved.html`) the page splits like Closet's: the
/// sidebar holds the title, the switch, search and filters, and the grid column holds the looks
/// or pictures, or the state that stands in for them. `part` says which this view draws.
///
/// Separate from `SavedLooksScreen` so snapshot tests can draw it from a model without navigation.
struct SavedLooksPage: View {
    @Bindable var model: SavedLooksModel
    var actions = SavedLooksActions()
    var part = BrowsePart.whole
    /// The look or picture showing beside the grid (iPad, Phase 15b). Tapping one then shows it
    /// there instead of opening it over the grid.
    var current: SavedLooksSelection?
    var opensBeside = false

    @Environment(\.closetIsStillImage) private var isStillImage

    /// Past this the controls read badly; the grid keeps the full width.
    static let controlsMaximumWidth: CGFloat = 640

    var body: some View {
        Group {
            if isStillImage {
                page
            } else {
                ScrollView(.vertical) { page }
                    .scrollDismissesKeyboard(.immediately)
            }
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
    }

    @ViewBuilder private var page: some View {
        switch part {
        case .whole:
            VStack(alignment: .leading, spacing: 0) {
                top
                switch model.tab {
                case .looks:
                    looksControls(chipLayout: .automatic)
                    looksBody
                case .pictures:
                    picturesControls(chipLayout: .automatic)
                    picturesBody
                }
            }
            .padding(.top, NookSpacing.small)
            .padding(.bottom, NookSpacing.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .sidebar:
            VStack(alignment: .leading, spacing: 0) {
                top
                switch model.tab {
                case .looks: looksControls(chipLayout: .wrap)
                case .pictures: picturesControls(chipLayout: .wrap)
                }
            }
            .padding(.top, NookSpacing.small)
            .padding(.bottom, NookSpacing.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .grid:
            VStack(alignment: .leading, spacing: 0) {
                switch model.tab {
                case .looks: looksBody
                case .pictures: picturesBody
                }
            }
            .padding(.top, NookSpacing.small)
            .padding(.bottom, NookSpacing.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The title and count, then Looks and Pictures.
    private var top: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, NookSpacing.screenMargin)
            NookSegmentedPicker(
                SavedLooksText.tabsTitle,
                selection: $model.tab,
                options: [
                    .init(
                        .looks, title: SavedLooksText.looksTab, systemImage: "bookmark",
                        identifier: "savedLooks.tab.looks"),
                    .init(
                        .pictures, title: SavedLooksText.picturesTab, systemImage: "camera",
                        identifier: "savedLooks.tab.pictures"),
                ]
            )
            .frame(maxWidth: 420)
            .padding(.horizontal, NookSpacing.screenMargin)
            .padding(.top, NookSpacing.medium)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
            Text(SavedLooksText.title)
                .nookTextStyle(.display)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let count = headerCount {
                Text(count)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "5 looks", or on Pictures "3 pictures".
    private var headerCount: String? {
        switch model.tab {
        case .looks: model.items.isEmpty ? nil : SavedLooksText.looks(model.items.count)
        case .pictures: model.pictureItems.isEmpty ? nil : TryOnText.pictures(model.pictureItems.count)
        }
    }

    // MARK: Looks

    /// The line about a look she just deleted, then search and the filters.
    @ViewBuilder private func looksControls(chipLayout: NookChipBarLayout) -> some View {
        if model.phase == .loaded {
            if let removal = model.lastRemoval {
                NookBanner(
                    LookDetailText.deleted(removal), systemImage: "trash", tone: .neutral,
                    actionTitle: YourLooksText.undo, action: actions.undoDelete
                )
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.top, NookSpacing.medium)
                .frame(maxWidth: Self.controlsMaximumWidth, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("savedLooks.deleted")
            }
            if !model.isEmpty {
                controls(prompt: SavedLooksText.searchPrompt, count: model.countText, chipLayout: chipLayout)
            }
        }
    }

    /// The looks, or the state that stands in for them.
    @ViewBuilder private var looksBody: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(SavedLooksText.loading)
                .stateCard()
                .padding(.top, NookSpacing.large)
        case .failed:
            NookErrorState(SavedLooksText.failedTitle, message: SavedLooksText.failedMessage, retry: actions.retry)
                .stateCard()
                .padding(.top, NookSpacing.large)
        case .loaded:
            if model.isEmpty {
                empty
            } else if model.hasNoMatches {
                noMatches(SavedLooksText.noMatchesTitle)
            } else {
                SavedLooksGrid(
                    items: model.shown, now: model.loadedAt, current: current.flatMap(\.lookID),
                    opensBeside: opensBeside, open: actions.open
                )
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.top, NookSpacing.medium)
            }
        }
    }

    /// The search field, the filters and, while filtering, the count line. One search and one
    /// set of chips for both tabs.
    private func controls(prompt: String, count: String, chipLayout: NookChipBarLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NookSearchField(prompt, text: $model.searchText, onSubmit: model.applySearchNow)
                .padding(.horizontal, NookSpacing.screenMargin)
            SavedLooksFilters(model: model, chipLayout: chipLayout)
                .padding(.top, NookSpacing.small)
            if model.filter.isActive {
                countLine(count)
                    .padding(.horizontal, NookSpacing.screenMargin)
                    .padding(.top, NookSpacing.xSmall)
            }
        }
        .padding(.top, NookSpacing.medium)
        .frame(maxWidth: Self.controlsMaximumWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "2 of 5 looks", with Clear (LR-09).
    private func countLine(_ count: String) -> some View {
        HStack(spacing: NookSpacing.small) {
            Text(count)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("savedLooks.count")
            Button {
                model.clearFilters()
            } label: {
                Text("Clear", bundle: .module, comment: "Clears every filter and the search")
            }
            .buttonStyle(.nook(.text, size: .small))
            .accessibilityLabel(Text(SavedLooksText.clearFilters))
            .accessibilityIdentifier("savedLooks.filter.clear")
        }
    }

    /// Nothing matches: says which filters are on, with Clear filters (LR-09.3).
    private func noMatches(_ title: String) -> some View {
        NookEmptyState(title, message: model.filterSummary, systemImage: "magnifyingglass") {
            NookButton(SavedLooksText.clearFilters, systemImage: "xmark", kind: .soft, fillsWidth: true) {
                model.clearFilters()
            }
            .accessibilityIdentifier("savedLooks.noMatches.clear")
        }
        .stateCard()
        .padding(.top, NookSpacing.large)
        .accessibilityIdentifier("savedLooks.noMatches")
    }

    /// RD-08.4: nothing saved yet says how to save a look, and offers Make your own.
    private var empty: some View {
        NookEmptyState(SavedLooksText.emptyTitle, message: SavedLooksText.emptyMessage, systemImage: "bookmark") {
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                ForEach(Array(SavedLooksText.emptySteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: NookSpacing.small) {
                        Text(verbatim: "\(index + 1).")
                            .nookTextStyle(.label)
                            .foregroundStyle(.nook.accent)
                            .accessibilityHidden(true)
                        Text(step)
                            .nookTextStyle(.body)
                            .foregroundStyle(.nook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            NookButton(SavedLooksText.makeYourOwn, kind: .soft, fillsWidth: true, action: actions.makeYourOwn)
                .accessibilityLabel(Text(SavedLooksText.makeYourOwnSpoken))
                .accessibilityIdentifier("savedLooks.empty.makeYourOwn")
        }
        .stateCard()
        .padding(.top, NookSpacing.large)
        .accessibilityIdentifier("savedLooks.empty")
    }

    // MARK: Pictures (12b)

    /// The line about a picture she just deleted, then search and the filters.
    @ViewBuilder private func picturesControls(chipLayout: NookChipBarLayout) -> some View {
        if model.picturesPhase == .loaded {
            if model.lastPictureRemoval != nil {
                NookBanner(
                    TryOnText.deleted, systemImage: "trash", tone: .neutral, actionTitle: YourLooksText.undo,
                    action: actions.undoPictureDelete
                )
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.top, NookSpacing.medium)
                .frame(maxWidth: Self.controlsMaximumWidth, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("savedLooks.pictureDeleted")
            }
            if !model.hasNoPictures {
                controls(prompt: TryOnText.searchPrompt, count: model.picturesCountText, chipLayout: chipLayout)
            }
        }
    }

    /// The pictures, or the state that stands in for them.
    @ViewBuilder private var picturesBody: some View {
        switch model.picturesPhase {
        case .loading:
            NookLoadingState(TryOnText.loading)
                .stateCard()
                .padding(.top, NookSpacing.large)
        case .failed:
            NookErrorState(TryOnText.failedTitle, message: SavedLooksText.failedMessage, retry: actions.retry)
                .stateCard()
                .padding(.top, NookSpacing.large)
        case .loaded:
            if model.hasNoPictures {
                picturesEmpty
            } else if model.picturesHaveNoMatches {
                noMatches(TryOnText.noMatchesTitle)
            } else {
                SavedPicturesGrid(
                    items: model.shownPictures, now: model.loadedAt, current: current.flatMap(\.pictureID),
                    opensBeside: opensBeside, open: actions.openPicture, openLook: actions.openLook
                )
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.top, NookSpacing.medium)
            }
        }
    }

    /// No pictures yet: what a picture is, that it needs a saved look, and how to make one.
    private var picturesEmpty: some View {
        NookEmptyState(TryOnText.emptyTitle, message: TryOnText.emptyMessage, systemImage: "camera") {
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                ForEach(Array(TryOnText.emptySteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: NookSpacing.small) {
                        Text(verbatim: "\(index + 1).")
                            .nookTextStyle(.label)
                            .foregroundStyle(.nook.accent)
                            .accessibilityHidden(true)
                        Text(step)
                            .nookTextStyle(.body)
                            .foregroundStyle(.nook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            NookButton(TryOnText.seeYourLooks, systemImage: "bookmark", kind: .soft, fillsWidth: true) {
                model.tab = .looks
            }
            .accessibilityIdentifier("savedLooks.pictures.seeLooks")
        }
        .stateCard()
        .padding(.top, NookSpacing.large)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("savedLooks.pictures.empty")
    }
}

extension View {
    /// A state's words on a soft tint, centred, as on Closet.
    fileprivate func stateCard() -> some View {
        self
            .background {
                NookRadius.shape(NookRadius.tile)
                    .fill(Color.nook.tint)
            }
            .padding(.horizontal, NookSpacing.screenMargin)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
    }
}
