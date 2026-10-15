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
struct ClosetScreen: View {
    @Environment(\.services) private var services
    @State private var model = ClosetModel()
    /// Kept by the root view, so another tab can open Suitcases or Laundry here (Phase 13).
    @Binding var path: [ClosetDestination]
    @State private var toast: NookToastMessage?
    /// Bumped after Undo on a deleted suitcase, so Suitcases reads its list again.
    @State private var suitcaseChanges = 0

    var body: some View {
        NavigationStack(path: $path) {
            ClosetPage(model: model, open: { path.append($0) }, retry: reload, discardDraft: discardDraft)
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
        .nookToast($toast)
        .task { await model.load(from: services) }
        .onChange(of: path) { old, new in
            // Back from a pushed screen: it may have changed a piece.
            if new.count < old.count { reload() }
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

#Preview {
    RootTabView(services: nil)
}
