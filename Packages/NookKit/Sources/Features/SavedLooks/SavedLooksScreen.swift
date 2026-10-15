import DesignSystem
import Models
import SwiftUI

/// A screen Saved Looks pushes.
nonisolated enum SavedLooksDestination: Hashable, Sendable {
    /// "+ Make your own" (LR-08.3, Phase 11).
    case makeYourOwnLook
    /// Look detail (Phase 12a), from the grid or a frame on the Home shelf.
    case look(Look.ID)
    /// A screen Closet also shows, opened from a look's piece: garment detail and what it opens.
    case closet(ClosetDestination)
}

/// Saved Looks (RD-08, LR-09): her saved looks with search and filters, look detail, and
/// "+ Make your own" (LR-08.3). The Pictures tab is a stand-in until 12b.
///
/// The path is the root view's, so a frame on the Home shelf can open a look here. The looks
/// reload each time the tab appears and each time a pushed screen closes, so a look saved on Your
/// looks, built in Make your own look or changed on its detail shows up. Delete look comes back
/// here with Undo, as Remove from closet does on Closet (LR-16.1).
struct SavedLooksScreen: View {
    @Binding var path: [SavedLooksDestination]

    @Environment(\.services) private var services
    @State private var model = SavedLooksModel()
    @State private var toast: NookToastMessage?
    /// Bumped when something changes a look from outside its detail (Undo on a removed piece),
    /// so the detail on screen reads it again.
    @State private var changes = 0

    var body: some View {
        NavigationStack(path: $path) {
            SavedLooksPage(
                model: model,
                actions: SavedLooksActions(
                    open: { path.append(.look($0.id)) },
                    undoDelete: undoDelete,
                    makeYourOwn: { path.append(.makeYourOwnLook) },
                    retry: reload
                )
            )
            .navigationTitle(SavedLooksText.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The big title is on the wall in the page instead.
                ToolbarItem(placement: .principal) {
                    Text(verbatim: "").accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(.makeYourOwnLook)
                    } label: {
                        // Words as well as the icon (playbook, Phase 6).
                        HStack(spacing: NookSpacing.xSmall) {
                            Image(systemName: "plus")
                            Text("Make your own", bundle: .module, comment: "Saved Looks toolbar button (RD-08, LR-08)")
                        }
                        .padding(.horizontal, NookSpacing.xSmall)
                    }
                    .accessibilityLabel(Text(SavedLooksText.makeYourOwnSpoken))
                    .accessibilityIdentifier("savedLooks.makeYourOwn")
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(.closet(.profile))
                    } label: {
                        Label {
                            Text("Profile", bundle: .module, comment: "Button: opens Profile")
                        } icon: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                    .accessibilityIdentifier("savedLooks.profile")
                }
            }
            .navigationDestination(for: SavedLooksDestination.self, destination: screen)
        }
        .nookToast($toast)
        .task { await model.load(from: services) }
        .onDisappear { model.lastRemoval = nil }
        .onChange(of: path) { old, new in
            // Back from a pushed screen: it may have saved or changed a look.
            if new.count < old.count { reload() }
        }
    }

    @ViewBuilder private func screen(for destination: SavedLooksDestination) -> some View {
        switch destination {
        case .makeYourOwnLook:
            LookBuilderScreen()
        case .look(let id):
            LookDetailScreen(
                lookID: id,
                changes: changes,
                openGarment: { garmentID, name in path.append(.closet(.garment(garmentID, name: name))) },
                deleted: lookDeleted)
        case .closet(let destination):
            closetScreen(destination)
        }
    }

    /// Garment detail and the screens it opens, as on Closet.
    @ViewBuilder private func closetScreen(_ destination: ClosetDestination) -> some View {
        switch destination {
        case .garment(let id, let name):
            GarmentDetailScreen(
                garmentID: id, name: name, open: { path.append(.closet($0)) }, back: goBack, removed: pieceRemoved)
        case .editPiece(let id, _, let resumesDraft):
            GarmentEditorScreen(
                target: .garment(id), resumesDraft: resumesDraft, saved: { _ in goBack() }, close: goBack)
        case .makeYourOwnLook(let id, _):
            LookBuilderScreen(startingPieceID: id)
        case .styleMe(let id, _):
            StyleMeScreen(
                startingPieceID: id,
                routes: StyleMeRoutes(
                    addPiece: { path.append(.closet(.addPiece(.photo))) },
                    openSuitcases: { path.append(.closet(.suitcases)) }))
        case .addPiece:
            GarmentEditorScreen(target: .newPiece, saved: { _ in goBack() }, close: goBack)
        default:
            StubScreen(
                title: destination.title, systemImage: destination.systemImage, identifier: destination.identifier)
        }
    }

    private func reload() {
        Task { await model.load(from: services) }
    }

    private func goBack() {
        if !path.isEmpty { path.removeLast() }
    }

    /// Delete look: back to the grid, with Undo in a toast and on a line over the looks, which
    /// stays until she leaves the tab, since a toast is easy to miss.
    private func lookDeleted(_ removal: SavedLookRemoval) {
        if case .look(let id) = path.last, id == removal.look.id {
            path.removeLast()
        }
        model.lastRemoval = removal
        reload()
        toast = NookToastMessage(
            LookDetailText.deleted(removal.name), systemImage: "trash", actionTitle: YourLooksText.undo,
            action: undoDelete)
    }

    private func undoDelete() {
        toast = nil
        Task { await model.undoLastRemoval(using: services) }
    }

    /// Remove from closet on a look's piece: back to the look, with Undo (LR-16.1). The look now
    /// shows the piece faded with Swap it.
    private func pieceRemoved(_ removal: GarmentRemoval) {
        if case .closet(.garment(let id, _)) = path.last, id == removal.garmentID {
            path.removeLast()
        }
        guard let closet = services?.closet else { return }
        toast = NookToastMessage(
            removal.message, systemImage: "checkmark",
            actionTitle: String(localized: "Undo", bundle: .module, comment: "Toast action")
        ) {
            Task {
                try? await removal.undo(in: closet)
                changes += 1
                await model.load(from: services)
            }
        }
    }
}
