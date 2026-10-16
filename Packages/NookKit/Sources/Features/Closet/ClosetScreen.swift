import DesignSystem
import Models
import SwiftUI

/// Closet: browse, search and filter her pieces (RD-13, LR-09, LR-11).
///
/// The title sits on the wall in the page's header, as in `closet.html`, so the navigation bar
/// only carries Add a piece and Profile. Tapping a piece opens its detail (7a), and the row at
/// the bottom opens Recently deleted, and Add a piece and Edit open the form (7b); Make your own
/// look opens from a piece's Style with this (11); Suitcases and Laundry live here too (13), and
/// Home's suitcase and hamper open them on this tab. The closet reloads each time the tab appears and each
/// time a pushed screen closes, so changes made there show up.
///
/// When she removes a piece on its detail, Closet goes back to the grid and shows a toast with
/// Undo (LR-16.1).
///
/// In a wide window (iPad, Phase 15a) a piece's detail shows beside the grid instead of over
/// it, and from 1,080 points the filters move into a sidebar (`WindowLayout.browse`). Every
/// other screen still opens over the whole width. Changing between layouts keeps what's open:
/// a piece beside the grid becomes a pushed detail in a narrow window, and back again.
struct ClosetScreen: View {
    @Environment(\.services) private var services
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = ClosetModel()
    /// Kept by the root view, so another tab can open Suitcases or Laundry here (Phase 13).
    @Binding var path: [ClosetDestination]
    @State private var toast: NookToastMessage?
    /// Bumped after Undo on a deleted suitcase, so Suitcases reads its list again.
    @State private var suitcaseChanges = 0
    /// The window's width, which picks the layout.
    @State private var width: CGFloat = 0
    /// The piece showing beside the grid, in the wide layouts.
    @State private var current: CurrentPiece?

    private var layout: BrowseLayout {
        WindowLayout.browse(width: width, horizontalSizeClass: horizontalSizeClass, dynamicTypeSize: dynamicTypeSize)
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationTitle(Text("Closet", bundle: .module, comment: "Navigation title on Closet"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // The big title is on the wall in the header instead.
                    ToolbarItem(placement: .principal) {
                        Text(verbatim: "").accessibilityHidden(true)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            path.append(.addPiece(.photo))
                        } label: {
                            // Words as well as the icon, as in the mockup: toolbars show labels
                            // as icons only.
                            HStack(spacing: NookSpacing.xSmall) {
                                Image(systemName: "plus")
                                Text("Add a piece", bundle: .module, comment: "Button: adds a piece to the closet")
                            }
                            .padding(.horizontal, NookSpacing.xSmall)
                        }
                        .accessibilityIdentifier("closet.addPiece")
                        .tourAnchor(ClosetTour.Anchor.addPiece, label: ClosetDestination.addPiece(.photo).title) {
                            path.append(.addPiece(.photo))
                        }
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            path.append(.profile)
                        } label: {
                            Label {
                                Text("Profile", bundle: .module, comment: "Button: opens Profile")
                            } icon: {
                                Image(systemName: "person.crop.circle")
                            }
                        }
                        .accessibilityIdentifier("closet.profile")
                    }
                }
                .navigationDestination(for: ClosetDestination.self, destination: screen)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = $0 })
        .onChange(of: layout) { old, new in keepWhatsOpen(from: old, to: new) }
        .nookToast($toast)
        .task { await model.load(from: services) }
        .onChange(of: path) { old, new in
            // Back from a pushed screen: it may have changed a piece.
            if new.count < old.count { reload() }
        }
    }

    // MARK: - Layouts

    private var root: some View {
        BrowseColumns(layout: layout, width: width, identifier: "closet", page: page) {
            detail
                .tourAnchor(
                    ClosetTour.Anchor.beside,
                    label: String(
                        localized: "The piece beside your closet", bundle: .module,
                        comment: "VoiceOver name of the column beside Closet's grid on iPad, in Closet's tour"))
        }
        // Closet's quick tour (Phase 16b), once her pieces are on screen: an empty closet, or one
        // still loading, doesn't have the search and filters it points at.
        .screenTour(
            ClosetTour.definition(detailBeside: layout.showsDetailBeside),
            isReady: model.phase == .loaded && !model.isEmpty && toast == nil)
    }

    private func page(_ part: BrowsePart) -> some View {
        ClosetPage(
            model: model, open: open, retry: reload, discardDraft: discardDraft, part: part,
            current: layout.showsDetailBeside ? current?.id : nil, opensBeside: layout.showsDetailBeside)
    }

    /// The piece beside the grid, or a quiet note until she picks one.
    @ViewBuilder private var detail: some View {
        if let current {
            GarmentDetailScreen(
                garmentID: current.id, name: current.name, open: { path.append($0) },
                back: { self.current = nil }, removed: pieceRemoved, isBeside: true
            )
            .id(current.id)
        } else {
            ClosetDetailPlaceholder()
        }
    }

    /// A piece opens beside the grid in the wide layouts, and over it otherwise.
    private func open(_ destination: ClosetDestination) {
        if layout.showsDetailBeside, case .garment(let id, let name) = destination {
            current = CurrentPiece(id: id, name: name)
        } else {
            path.append(destination)
        }
    }

    /// Turning the iPad or resizing the window keeps what she's looking at (PRD §7.2): a piece
    /// beside the grid is pushed when the window gets narrow, and a pushed piece moves back
    /// beside the grid when it gets wide again.
    private func keepWhatsOpen(from old: BrowseLayout, to new: BrowseLayout) {
        switch (old.showsDetailBeside, new.showsDetailBeside) {
        case (true, false):
            if let current, path.isEmpty {
                path = [.garment(current.id, name: current.name)]
            }
            current = nil
        case (false, true):
            if path.count == 1, case .garment(let id, let name) = path[0] {
                current = CurrentPiece(id: id, name: name)
                path = []
            }
        default:
            break
        }
    }

    @ViewBuilder private func screen(for destination: ClosetDestination) -> some View {
        switch destination {
        case .garment(let id, let name):
            GarmentDetailScreen(
                garmentID: id, name: name, open: { path.append($0) }, back: goBack, removed: pieceRemoved)
        case .recentlyDeleted:
            RecentlyDeletedScreen()
        case .styleMe(let id, _):
            StyleMeScreen(startingPieceID: id, routes: styleMeRoutes)
        case .styleMeFrom(let source):
            StyleMeScreen(source: source, routes: styleMeRoutes)
        case .suitcases:
            SuitcasesScreen(open: { path.append($0) }, changes: suitcaseChanges)
        case .allSuitcases:
            AllSuitcasesScreen(open: { path.append($0) })
        case .suitcase(let id, let name, let startsPacking):
            SuitcaseDetailScreen(
                suitcaseID: id, name: name, startsPacking: startsPacking, open: { path.append($0) }, back: goBack,
                deleted: suitcaseDeleted)
        case .laundry:
            LaundryScreen(open: { path.append($0) })
        case .addPiece(let start):
            GarmentEditorScreen(
                target: .newPiece, firstStep: start == .words ? .words : .choose, resumesDraft: start == .resume,
                saved: pieceSaved, close: goBack)
        case .editPiece(let id, _, let resumesDraft):
            GarmentEditorScreen(target: .garment(id), resumesDraft: resumesDraft, saved: pieceSaved, close: goBack)
        case .makeYourOwnLook(let id, _):
            LookBuilderScreen(startingPieceID: id)
        case .profile:
            ProfileScreen()
        }
    }

    private func reload() {
        Task { await model.load(from: services) }
    }

    private var styleMeRoutes: StyleMeRoutes {
        StyleMeRoutes(
            addPiece: { path.append(.addPiece(.photo)) },
            openSuitcases: { path.append(.suitcases) },
            openSuitcase: { id, name in path.append(.suitcase(id, name: name)) })
    }

    /// Delete suitcase: back to where she came from, with Undo, which puts back the same
    /// suitcase and the source it was.
    private func suitcaseDeleted(_ change: SuitcaseChange) {
        if case .suitcase(let id, _, _) = path.last, id == change.suitcase.id {
            path.removeLast()
        }
        guard let services else { return }
        toast = NookToastMessage(
            change.message, systemImage: "checkmark",
            actionTitle: String(localized: "Undo", bundle: .module, comment: "Toast action")
        ) {
            Task {
                try? await change.undo(in: services)
                suitcaseChanges += 1
                await model.load(from: services)
            }
        }
    }

    private func discardDraft() {
        guard let drafts = services?.drafts else { return }
        Task { await model.discardDraft(in: drafts) }
    }

    private func goBack() {
        if !path.isEmpty { path.removeLast() }
    }

    /// Add a piece or Edit saved: the form closes. A new piece shows at the top of the grid, an
    /// edited one on its detail, which reloads as it appears.
    private func pieceSaved(_ saved: GarmentEditorModel.Saved) {
        goBack()
        reload()
        switch saved {
        case .added(let garment):
            toast = NookToastMessage(
                String(
                    localized: "\(garment.name) is in your closet", bundle: .module,
                    comment: "Toast after Add a piece, with the piece's name"),
                systemImage: "checkmark")
        case .updated:
            toast = NookToastMessage(
                String(localized: "Changes saved", bundle: .module, comment: "Toast after editing a piece"),
                systemImage: "checkmark")
        }
    }

    /// Back to the grid, with Undo (LR-16.1). Undo puts the piece back and reloads.
    private func pieceRemoved(_ removal: GarmentRemoval) {
        if case .garment(let id, _) = path.last, id == removal.garmentID {
            path.removeLast()
        }
        if current?.id == removal.garmentID {
            current = nil
        }
        reload()
        guard let closet = services?.closet else { return }
        toast = NookToastMessage(
            removal.message, systemImage: "checkmark",
            actionTitle: String(localized: "Undo", bundle: .module, comment: "Toast action")
        ) {
            Task {
                try? await removal.undo(in: closet)
                await model.load(from: services)
            }
        }
    }
}

/// Beside the grid before she picks a piece.
struct ClosetDetailPlaceholder: View {
    var body: some View {
        BrowseDetailPlaceholder(
            title: String(localized: "Pick a piece", bundle: .module, comment: "Beside Closet's grid on iPad"),
            message: String(
                localized: "Its details show here, next to your closet.", bundle: .module,
                comment: "Beside Closet's grid on iPad, before she picks a piece"),
            systemImage: "hanger")
    }
}

/// The piece showing beside the grid: its ID, and the name to show until it loads.
private struct CurrentPiece: Equatable {
    let id: Garment.ID
    let name: String
}

#Preview {
    RootTabView(services: nil)
}
