import DesignSystem
import Models
import SwiftUI

/// Suitcases (Phase 13, RD-09, LR-17, FR-67), pushed on Closet's stack: from Closet's Suitcases
/// tile, and from Home's suitcase, which opens it on the Closet tab.
///
/// Choosing a source saves it at once: Home's suitcase shows it, the next Style Me starts from
/// it, and it's marked as used, so it joins the favourites next time (RD-09.2). A toast says so,
/// with Style me. Choosing an empty suitcase leaves the source as it was and offers to pack it.
/// "+ Add a suitcase" asks for a name and a picture, then opens the new suitcase to pack it.
struct SuitcasesScreen: View {
    let open: (ClosetDestination) -> Void
    /// Bumped by Closet when something outside changed her suitcases (Undo after a delete), so
    /// the list reads them again.
    var changes = 0

    @Environment(\.services) private var services
    @State private var model = SuitcasesModel()
    @State private var toast: NookToastMessage?
    @State private var showsAdd = false
    /// The suitcase just made, opened once the sheet has gone.
    @State private var made: Suitcase?

    var body: some View {
        SuitcasesPage(
            model: model,
            actions: SuitcasesActions(
                retry: reload,
                choose: choose,
                open: { open(.suitcase($0.id, name: $0.name)) },
                seeAll: { open(.allSuitcases) },
                add: { showsAdd = true }
            )
        )
        .navigationTitle(SuitcasesText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The big title is on the wall instead.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
            ToolbarItem(placement: .topBarTrailing) {
                AddSuitcaseToolbarButton { showsAdd = true }
                    .tourAnchor(SuitcasesTour.Anchor.add, label: SuitcasesText.addSuitcase) { showsAdd = true }
            }
        }
        .addSuitcaseSheet(isPresented: $showsAdd, model: model, made: $made) { suitcase in
            open(.suitcase(suitcase.id, name: suitcase.name, startsPacking: true))
        }
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task { await model.load(from: services) }
        .onChange(of: changes) { reload() }
        // Suitcases' quick tour (Phase 16b), once she has a favourite to choose.
        .screenTour(
            SuitcasesTour.definition,
            isReady: model.phase == .loaded && !model.favorites.isEmpty && !showsAdd && made == nil && toast == nil)
    }

    private func reload() {
        Task { await model.load(from: services) }
    }

    private func choose(_ source: WardrobeSource) {
        Task {
            toast = await SourceChoiceToast.make(choosing: source, model: model, services: services, open: open)
        }
    }
}

/// The toast after choosing a source, shared by Suitcases and All suitcases.
enum SourceChoiceToast {
    @MainActor
    static func make(
        choosing source: WardrobeSource, model: SuitcasesModel, services: NookServices?,
        open: @escaping (ClosetDestination) -> Void
    ) async -> NookToastMessage? {
        do {
            switch try await model.choose(source, in: services) {
            case .chosen:
                return NookToastMessage(
                    SuitcasesText.nowUsing(model.name(of: source)), systemImage: "checkmark",
                    actionTitle: SuitcasesText.styleMe
                ) {
                    open(.styleMeFrom(source))
                }
            case .empty(let suitcase):
                return NookToastMessage(
                    SuitcasesText.isEmpty(suitcase.name), systemImage: "suitcase",
                    actionTitle: SuitcasesText.packIt
                ) {
                    open(.suitcase(suitcase.id, name: suitcase.name, startsPacking: true))
                }
            case .unchanged:
                return nil
            }
        } catch {
            return NookToastMessage(SuitcasesText.failed, systemImage: "exclamationmark.circle")
        }
    }
}

/// "+ Add a suitcase" in the navigation bar, with its words as well as the icon (LR-17).
struct AddSuitcaseToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NookSpacing.xSmall) {
                Image(systemName: "plus")
                Text(SuitcasesText.addSuitcase)
            }
            .padding(.horizontal, NookSpacing.xSmall)
        }
        .accessibilityIdentifier("suitcases.add")
    }
}

extension View {
    /// The "+ Add a suitcase" sheet: a name and a picture, then the new suitcase opens to be
    /// packed once the sheet has gone (LR-17.2).
    func addSuitcaseSheet(
        isPresented: Binding<Bool>, model: SuitcasesModel, made: Binding<Suitcase?>,
        openMade: @escaping (Suitcase) -> Void
    ) -> some View {
        modifier(AddSuitcaseSheet(isPresented: isPresented, model: model, made: made, openMade: openMade))
    }
}

private struct AddSuitcaseSheet: ViewModifier {
    @Binding var isPresented: Bool
    let model: SuitcasesModel
    @Binding var made: Suitcase?
    let openMade: (Suitcase) -> Void

    @Environment(\.services) private var services

    private func openMadeSuitcase() {
        if let suitcase = made {
            made = nil
            openMade(suitcase)
        }
    }

    func body(content: Content) -> some View {
        content
            .nookSheet(
                isPresented: $isPresented,
                title: SuitcasesText.addSuitcase,
                subtitle: String(
                    localized: "Give it a name and a picture, then pick what goes in.", bundle: .module,
                    comment: "Under the Add a suitcase sheet's title"),
                detents: [.large],
                onDismiss: openMadeSuitcase
            ) {
                SuitcaseEditor(purpose: .add, problem: { model.nameProblem($0) }) { name, icon in
                    do {
                        made = try await model.create(name: name, icon: icon, in: services)
                        isPresented = false
                        return true
                    } catch {
                        return false
                    }
                }
            }
    }
}

/// All suitcases (RD-09, RD-09.3): every suitcase with search, the favourites first, the
/// archived ones only under their filter, and the main closet.
struct AllSuitcasesScreen: View {
    let open: (ClosetDestination) -> Void

    @Environment(\.services) private var services
    @State private var model = SuitcasesModel()
    @State private var toast: NookToastMessage?
    @State private var showsAdd = false
    @State private var made: Suitcase?

    var body: some View {
        AllSuitcasesPage(
            model: model,
            actions: SuitcasesActions(
                retry: { Task { await model.load(from: services) } },
                choose: { source in
                    Task {
                        toast = await SourceChoiceToast.make(
                            choosing: source, model: model, services: services, open: open)
                    }
                },
                open: { open(.suitcase($0.id, name: $0.name)) },
                add: { showsAdd = true }
            )
        )
        .navigationTitle(SuitcasesText.allTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
            ToolbarItem(placement: .topBarTrailing) {
                AddSuitcaseToolbarButton { showsAdd = true }
            }
        }
        .addSuitcaseSheet(isPresented: $showsAdd, model: model, made: $made) { suitcase in
            open(.suitcase(suitcase.id, name: suitcase.name, startsPacking: true))
        }
        .overlay {
            Color.clear
                .nookToast($toast)
        }
        .task { await model.load(from: services) }
    }
}

/// All suitcases' content: the title on the wall, search, the Archived filter when there are
/// any, then the suitcases on a soft tint and the main closet.
struct AllSuitcasesPage: View {
    @Bindable var model: SuitcasesModel
    var actions = SuitcasesActions()

    @Environment(\.closetIsStillImage) private var isStillImage

    var body: some View {
        if isStillImage {
            page
                .background(Color.nook.floor)
        } else {
            ScrollView(.vertical) {
                page
            }
            .scrollDismissesKeyboard(.immediately)
            .background(FloorBackground())
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            WallHeader(
                title: SuitcasesText.allTitle,
                detail: model.phase == .loaded ? SuitcasesText.suitcaseCount(model.shelf.all.count) : nil
            ) {
                EmptyView()
            }
            content
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.top, NookSpacing.medium)
                .padding(.bottom, NookSpacing.xxxLarge)
                .readablePane()
                .background(Color.nook.floor)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(String(localized: "Opening your suitcases", bundle: .module, comment: "Suitcases loading"))
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
                NookSearchField(
                    String(localized: "Search suitcases", bundle: .module, comment: "All suitcases search prompt"),
                    text: $model.searchText)
                if !model.shelf.archived.isEmpty {
                    NookChip(
                        String(
                            localized: "Archived · \(model.shelf.archived.count)", bundle: .module,
                            comment: "All suitcases: filter that shows archived suitcases, with how many"),
                        systemImage: "archivebox", isSelected: model.showsArchived
                    ) {
                        model.showsArchived.toggle()
                    }
                    .accessibilityIdentifier("allSuitcases.archived")
                }
                list
            }
        }
    }

    @ViewBuilder private var list: some View {
        let favorites = model.matching(model.favorites)
        let others = model.matching(model.others)
        let archived = model.showsArchived ? model.matching(model.shelf.archived) : []
        if favorites.isEmpty && others.isEmpty && archived.isEmpty && !model.searchText.isEmpty {
            NookEmptyState(
                String(localized: "No suitcases match", bundle: .module, comment: "All suitcases: nothing matches"),
                message: String(
                    localized: "“\(model.searchText)”", bundle: .module, comment: "Typed search, in quotes"),
                systemImage: "magnifyingglass"
            ) {
                NookButton(
                    String(localized: "Clear search", bundle: .module, comment: "Button: empties the search"),
                    systemImage: "xmark", kind: .soft, fillsWidth: true
                ) {
                    model.searchText = ""
                }
            }
            .floorCard()
        } else {
            VStack(alignment: .leading, spacing: 2) {
                section(SuitcasesText.favourites, favorites)
                section(SuitcasesText.otherSuitcases, others)
                section(SuitcasesText.archived, archived)
                if model.searchText.isEmpty {
                    NookDivider()
                        .padding(.vertical, NookSpacing.xSmall)
                    MainClosetSourceRow(model: model, choose: actions.choose)
                }
            }
            .padding(NookSpacing.xSmall)
            .floorCard()
        }
        if !model.hasSuitcases {
            NookButton(
                SuitcasesText.addSuitcase, systemImage: "plus", kind: .soft, fillsWidth: true, action: actions.add)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ suitcases: [Suitcase]) -> some View {
        if !suitcases.isEmpty {
            NookSectionHeader(title)
                .padding(.horizontal, NookSpacing.small)
                .padding(.top, NookSpacing.xSmall)
            ForEach(suitcases) { suitcase in
                SuitcaseSourceRow(suitcase: suitcase, model: model, choose: actions.choose, open: actions.open)
            }
        }
    }
}
