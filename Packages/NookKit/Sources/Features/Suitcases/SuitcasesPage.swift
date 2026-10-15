import DesignSystem
import Models
import SwiftUI

/// What Suitcases' buttons do. The screen fills these in; snapshot tests leave them empty.
struct SuitcasesActions {
    var retry: () -> Void = {}
    var choose: (WardrobeSource) -> Void = { _ in }
    var open: (Suitcase) -> Void = { _ in }
    var seeAll: () -> Void = {}
    var add: () -> Void = {}
}

/// Suitcases, top to bottom (`suitcases.html`, RD-09, LR-17): the title on the wall, the hall
/// with her three favourites, then on the floor the favourites again as rows, See all when there
/// are more than three, the main closet, "+ Add a suitcase" and a line about what a source
/// does. With no suitcases yet, the hall stands empty and the floor explains what a suitcase is.
///
/// "+ Add a suitcase" is also in the navigation bar, so it shows without scrolling however many
/// suitcases she has (LR-17.1). At the accessibility text sizes the hall is left out: it only
/// repeats the rows, and its tags can't grow.
struct SuitcasesPage: View {
    let model: SuitcasesModel
    var actions = SuitcasesActions()

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if isStillImage {
            page
                .background(Color.nook.floor)
        } else {
            ScrollView(.vertical) {
                page
            }
            .background(FloorBackground())
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                WallHeader(title: SuitcasesText.title, hasFloorLine: !showsHall, hasBackground: false) {
                    EmptyView()
                }
                if showsHall {
                    SuitcasesHall(
                        favorites: model.favorites, pieceCount: model.pieceCount(of:), chosen: model.chosen,
                        choose: { actions.choose(.suitcase($0.id)) }
                    )
                }
            }
            // One wall behind the title and the hall, so its gradient doesn't start again.
            .background(Color.nook.wallGradient)
            floor
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.top, NookSpacing.medium)
                .padding(.bottom, NookSpacing.xxxLarge)
                .readablePane()
                .background(Color.nook.floor)
        }
    }

    private var showsHall: Bool {
        model.phase == .loaded && !dynamicTypeSize.isAccessibilitySize
    }

    @ViewBuilder private var floor: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(
                String(localized: "Opening your suitcases", bundle: .module, comment: "Suitcases loading")
            )
            .floorCard()
        case .failed:
            NookErrorState(
                String(localized: "Your suitcases didn’t load", bundle: .module, comment: "Suitcases error title"),
                message: String(
                    localized: "Nothing was lost. Try again in a moment.", bundle: .module,
                    comment: "Closet error message"),
                retry: actions.retry
            )
            .floorCard()
        case .loaded:
            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                if model.sourceWentAway {
                    NookBanner(
                        String(
                            localized:
                                "The suitcase you were styling from isn’t there any more, so Style Me uses Main closet.",
                            bundle: .module, comment: "Suitcases: the remembered suitcase was deleted or archived"),
                        systemImage: "info.circle", tone: .neutral
                    )
                }
                if model.hasSuitcases {
                    list
                } else {
                    empty
                }
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                if !model.favorites.isEmpty {
                    NookSectionHeader(SuitcasesText.favourites, detail: SuitcasesText.favouritesNote)
                        .padding(.horizontal, NookSpacing.small)
                        .padding(.bottom, NookSpacing.xSmall)
                    ForEach(model.favorites) { suitcase in
                        SuitcaseSourceRow(suitcase: suitcase, model: model, choose: actions.choose, open: actions.open)
                    }
                }
                if model.shelf.showsSeeAll || !model.shelf.archived.isEmpty {
                    seeAll
                }
                NookDivider()
                MainClosetSourceRow(model: model, choose: actions.choose)
            }
            .padding(NookSpacing.xSmall)
            .floorCard()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                Text("Source for Style Me", bundle: .module, comment: "Suitcases: name of the list of sources"))
            addButton
            note
        }
    }

    /// "See all 5" (RD-09): every suitcase, and the archived ones under their filter.
    private var seeAll: some View {
        Button(action: actions.seeAll) {
            HStack {
                Text("See all suitcases", bundle: .module, comment: "Suitcases: opens every suitcase")
                    .nookTextStyle(.button)
                    .foregroundStyle(.nook.accent)
                Spacer(minLength: NookSpacing.small)
                Text(model.shelf.all.count.formatted())
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                Image(systemName: "chevron.right")
                    .font(Font.nook.label)
                    .foregroundStyle(.nook.chevron)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(ClosetPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SuitcasesText.seeAll(model.shelf.all.count)))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("suitcases.seeAll")
    }

    private var addButton: some View {
        NookButton(SuitcasesText.addSuitcase, systemImage: "plus", kind: .soft, fillsWidth: true, action: actions.add)
            .accessibilityIdentifier("suitcases.add.bottom")
    }

    private var note: some View {
        Text(SuitcasesText.sourceNote)
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(NookSpacing.small)
            .frame(maxWidth: .infinity)
            .floorCard()
    }

    /// No suitcases yet (`?state=empty`): what a suitcase is, "+ Add a suitcase" (LR-17), and
    /// the main closet, which Style Me uses until then.
    private var empty: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            NookEmptyState(
                String(localized: "No suitcases yet", bundle: .module, comment: "Suitcases: empty title"),
                message: String(
                    localized:
                        "A suitcase is a smaller set of your pieces, for a trip or a second home. Style Me can then pick from just what’s packed.",
                    bundle: .module, comment: "Suitcases: empty message"),
                systemImage: "suitcase"
            ) {
                NookButton(SuitcasesText.addSuitcase, systemImage: "plus", fillsWidth: true, action: actions.add)
                    .accessibilityIdentifier("suitcases.add.empty")
            }
            .floorCard()
            VStack(spacing: 0) {
                MainClosetSourceRow(model: model, choose: actions.choose)
                Text(
                    "Style Me uses your whole closet until you pack a suitcase.", bundle: .module,
                    comment: "Suitcases: under the main closet when there are no suitcases"
                )
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(NookSpacing.small)
            }
            .padding(NookSpacing.xSmall)
            .floorCard()
        }
    }
}
