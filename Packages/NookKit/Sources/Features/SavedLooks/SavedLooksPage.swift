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
}

/// Saved Looks' content, top to bottom (`saved.html`, RD-08): the title and count, the Looks and
/// Pictures switch, then on Looks the search field, the piece and colour filters (LR-09), the
/// count line with Clear, and the grid. An empty Saved Looks explains how to save a look
/// (RD-08.4); a search with no matches names the filters, with Clear filters (LR-09.3).
///
/// Separate from `SavedLooksScreen` so snapshot tests can draw it from a model without navigation.
struct SavedLooksPage: View {
    @Bindable var model: SavedLooksModel
    var actions = SavedLooksActions()

    @Environment(\.closetIsStillImage) private var isStillImage

    /// Past this the controls read badly; the grid keeps the full width (iPad's own layout is 15b).
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

    private var page: some View {
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
            switch model.tab {
            case .looks: looks
            case .pictures: pictures
            }
        }
        .padding(.top, NookSpacing.small)
        .padding(.bottom, NookSpacing.xxxLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
            Text(SavedLooksText.title)
                .nookTextStyle(.display)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if !model.items.isEmpty {
                Text(SavedLooksText.looks(model.items.count))
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Looks

    @ViewBuilder private var looks: some View {
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
            if let removal = model.lastRemoval {
                NookBanner(
                    LookDetailText.deleted(removal.name), systemImage: "trash", tone: .neutral,
                    actionTitle: YourLooksText.undo, action: actions.undoDelete
                )
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.top, NookSpacing.medium)
                .frame(maxWidth: Self.controlsMaximumWidth, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("savedLooks.deleted")
            }
            if model.isEmpty {
                empty
            } else {
                controls
                if model.hasNoMatches {
                    noMatches
                } else {
                    SavedLooksGrid(items: model.shown, now: model.loadedAt, open: actions.open)
                        .padding(.horizontal, NookSpacing.screenMargin)
                        .padding(.top, NookSpacing.medium)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            NookSearchField(SavedLooksText.searchPrompt, text: $model.searchText, onSubmit: model.applySearchNow)
                .padding(.horizontal, NookSpacing.screenMargin)
            SavedLooksFilters(model: model)
                .padding(.top, NookSpacing.small)
            if model.filter.isActive {
                countLine
                    .padding(.horizontal, NookSpacing.screenMargin)
                    .padding(.top, NookSpacing.xSmall)
            }
        }
        .padding(.top, NookSpacing.medium)
        .frame(maxWidth: Self.controlsMaximumWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "2 of 5 looks", with Clear (LR-09).
    private var countLine: some View {
        HStack(spacing: NookSpacing.small) {
            Text(model.countText)
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

    /// No looks match: says which filters are on, with Clear filters (LR-09.3).
    private var noMatches: some View {
        NookEmptyState(SavedLooksText.noMatchesTitle, message: model.filterSummary, systemImage: "magnifyingglass") {
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

    private var pictures: some View {
        NookEmptyState(SavedLooksText.picturesTitle, message: SavedLooksText.picturesMessage, systemImage: "camera")
            .stateCard()
            .padding(.top, NookSpacing.large)
            .accessibilityIdentifier("savedLooks.pictures")
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
