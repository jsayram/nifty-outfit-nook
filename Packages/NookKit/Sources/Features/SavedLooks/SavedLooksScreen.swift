import DesignSystem
import Models
import SwiftUI

/// A screen Saved Looks pushes.
nonisolated enum SavedLooksDestination: Hashable, Sendable {
    /// "+ Make your own" (LR-08.3, Phase 11).
    case makeYourOwnLook
    /// Look detail (Phase 12a), from the grid, a picture, or a frame on the Home shelf.
    case look(Look.ID)
    /// Picture detail (Phase 12b), from the Pictures tab, a look, or Try it on.
    case picture(TryOnPicture.ID)
    /// A screen Closet also shows, opened from a look's piece: garment detail and what it opens.
    case closet(ClosetDestination)
}

/// Saved Looks (RD-08, LR-09): her saved looks and her try-on pictures with search and filters,
/// look detail, picture detail, and "+ Make your own" (LR-08.3).
///
/// A picture opens its look and a look its pictures (RD-08.2). Going from one to the other and
/// back goes back rather than piling up copies: See the look on a picture opened from that look
/// is Back.
///
/// The path is the root view's, so a frame on the Home shelf can open a look here. The looks
/// reload each time the tab appears and each time a pushed screen closes, so a look saved on Your
/// looks, built in Make your own look or changed on its detail shows up. Delete look comes back
/// here with Undo, as Remove from closet does on Closet (LR-16.1).
///
/// In a wide window (iPad, Phase 15b) a look or a picture shows beside the grid instead of over
/// it, and from 1,080 points the search and filters move into a sidebar, as on Closet
/// (`WindowLayout.browse`). Each tab keeps its own look or picture beside it, so what's beside
/// the grid is always one of the grid's own; going from a picture to its look, or from a look to
/// one of its pictures, switches tab.
/// Every other screen still opens over the whole width. Changing between layouts keeps what's
/// open: a look beside the grid becomes a pushed look in a narrow window, and back again.
struct SavedLooksScreen: View {
    @Binding var path: [SavedLooksDestination]

    @Environment(\.services) private var services
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = SavedLooksModel()
    @State private var toast: NookToastMessage?
    /// Bumped when something changes a look from outside its detail (Undo on a removed piece),
    /// so the detail on screen reads it again.
    @State private var changes = 0
    /// The window's width, which picks the layout.
    @State private var width: CGFloat = 0
    /// The look beside the Looks tab's grid and the picture beside the Pictures tab's, in the
    /// wide layouts.
    @State private var besideLook: Look.ID?
    @State private var besidePicture: TryOnPicture.ID?

    /// What's beside the grid on the tab that's showing.
    private var current: SavedLooksSelection? {
        switch model.tab {
        case .looks: besideLook.map(SavedLooksSelection.look)
        case .pictures: besidePicture.map(SavedLooksSelection.picture)
        }
    }

    private var layout: BrowseLayout {
        WindowLayout.browse(width: width, horizontalSizeClass: horizontalSizeClass, dynamicTypeSize: dynamicTypeSize)
    }

    var body: some View {
        NavigationStack(path: $path) {
            BrowseColumns(layout: layout, width: width, identifier: "savedLooks", page: page) { detail }
                // Saved Looks' quick tour (Phase 16b), on the Looks tab once she has saved looks.
                .screenTour(
                    SavedLooksTour.definition,
                    isReady: model.phase == .loaded && model.tab == .looks && !model.isEmpty && !model.hasNoMatches
                        && toast == nil
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
                                Text(
                                    "Make your own", bundle: .module,
                                    comment: "Saved Looks toolbar button (RD-08, LR-08)")
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
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = $0 })
        .onChange(of: layout) { old, new in keepWhatsOpen(from: old, to: new) }
        .nookToast($toast)
        .task { await model.load(from: services) }
        .onDisappear {
            model.lastRemoval = nil
            model.lastPictureRemoval = nil
        }
        .onChange(of: path) { old, new in
            // Back from a pushed screen: it may have saved or changed a look or a picture.
            if new.count < old.count { reload() }
            if old.isEmpty {
                showPicturesIfOpeningOne()
                moveBesideIfWide()
            }
        }
        .onAppear {
            showPicturesIfOpeningOne()
            moveBesideIfWide()
        }
    }

    // MARK: - Layouts

    private func page(_ part: BrowsePart) -> some View {
        SavedLooksPage(
            model: model,
            actions: SavedLooksActions(
                open: { openLook($0.id) },
                undoDelete: undoDelete,
                makeYourOwn: { path.append(.makeYourOwnLook) },
                retry: reload,
                openPicture: { openPicture($0.id) },
                openLook: { openLook($0.id) },
                undoPictureDelete: undoPictureDelete
            ),
            part: part,
            current: layout.showsDetailBeside ? current : nil,
            opensBeside: layout.showsDetailBeside
        )
    }

    /// The look or picture beside the grid, or a quiet note until she picks one.
    @ViewBuilder private var detail: some View {
        switch current {
        case .look(let id):
            lookDetail(id, isBeside: true)
                .id(id)
        case .picture(let id):
            pictureDetail(id, isBeside: true)
                .id(id)
        case nil:
            switch model.tab {
            case .looks:
                BrowseDetailPlaceholder(
                    title: SavedLooksText.pickLookTitle, message: SavedLooksText.pickLookMessage,
                    systemImage: "bookmark")
            case .pictures:
                BrowseDetailPlaceholder(
                    title: SavedLooksText.pickPictureTitle, message: SavedLooksText.pickPictureMessage,
                    systemImage: "camera")
            }
        }
    }

    private func lookDetail(_ id: Look.ID, isBeside: Bool) -> some View {
        LookDetailScreen(
            lookID: id,
            changes: changes,
            openGarment: { garmentID, name in path.append(.closet(.garment(garmentID, name: name))) },
            openPicture: openPicture,
            deleted: lookDeleted,
            isBeside: isBeside)
    }

    private func pictureDetail(_ id: TryOnPicture.ID, isBeside: Bool) -> some View {
        PictureDetailScreen(
            pictureID: id, seeLook: { openLook($0.id) }, deleted: pictureDeleted, isBeside: isBeside)
    }

    /// Turning the iPad or resizing the window keeps what she's looking at (PRD §7.2): a look or
    /// picture beside the grid is pushed when the window gets narrow, under anything it opened,
    /// and a pushed one moves back beside the grid when it gets wide again.
    private func keepWhatsOpen(from old: BrowseLayout, to new: BrowseLayout) {
        switch (old.showsDetailBeside, new.showsDetailBeside) {
        case (true, false):
            if let current {
                path.insert(current.destination, at: 0)
            }
            besideLook = nil
            besidePicture = nil
        case (false, true):
            moveBesideIfWide()
        default:
            break
        }
    }

    /// In a wide layout, a look or picture opened over the grid (from the Home shelf, Try it on,
    /// or before the window widened) moves beside it. Anything it opened stays pushed.
    private func moveBesideIfWide() {
        guard layout.showsDetailBeside, let first = path.first, let selection = SavedLooksSelection(first) else {
            return
        }
        let looksAndPictures = path.compactMap(SavedLooksSelection.init)
        if looksAndPictures.count == path.count, let last = looksAndPictures.last {
            show(last)
            path = []
        } else {
            show(selection)
            path.removeFirst()
        }
    }

    /// Shows a look or picture beside the grid, on its own tab.
    private func show(_ selection: SavedLooksSelection) {
        switch selection {
        case .look(let id):
            besideLook = id
            if model.tab != .looks { model.tab = .looks }
        case .picture(let id):
            besidePicture = id
            if model.tab != .pictures { model.tab = .pictures }
        }
    }

    @ViewBuilder private func screen(for destination: SavedLooksDestination) -> some View {
        switch destination {
        case .makeYourOwnLook:
            LookBuilderScreen()
        case .look(let id):
            lookDetail(id, isBeside: false)
        case .picture(let id):
            pictureDetail(id, isBeside: false)
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
            StyleMeScreen(startingPieceID: id, routes: styleMeRoutes)
        case .styleMeFrom(let source):
            StyleMeScreen(source: source, routes: styleMeRoutes)
        case .suitcases:
            SuitcasesScreen(open: { path.append(.closet($0)) })
        case .allSuitcases:
            AllSuitcasesScreen(open: { path.append(.closet($0)) })
        case .suitcase(let id, let name, let startsPacking):
            SuitcaseDetailScreen(
                suitcaseID: id, name: name, startsPacking: startsPacking, open: { path.append(.closet($0)) },
                back: goBack, deleted: suitcaseDeleted)
        case .laundry:
            LaundryScreen(open: { path.append(.closet($0)) })
        case .addPiece:
            GarmentEditorScreen(target: .newPiece, saved: { _ in goBack() }, close: goBack)
        default:
            StubScreen(
                title: destination.title, systemImage: destination.systemImage, identifier: destination.identifier)
        }
    }

    /// Try it on's See the picture opens a picture here from another tab, before this tab may
    /// have appeared. Back from it should land on the pictures.
    private func showPicturesIfOpeningOne() {
        if case .picture = path.first { model.tab = .pictures }
    }

    private func reload() {
        Task { await model.load(from: services) }
    }

    private var styleMeRoutes: StyleMeRoutes {
        StyleMeRoutes(
            addPiece: { path.append(.closet(.addPiece(.photo))) },
            openSuitcases: { path.append(.closet(.suitcases)) },
            openSuitcase: { id, name in path.append(.closet(.suitcase(id, name: name))) })
    }

    /// Delete suitcase, from a suitcase opened on a piece's detail: back to the piece, with Undo.
    private func suitcaseDeleted(_ change: SuitcaseChange) {
        goBack()
        guard let services else { return }
        toast = NookToastMessage(
            change.message, systemImage: "checkmark",
            actionTitle: String(localized: "Undo", bundle: .module, comment: "Toast action")
        ) {
            Task { try? await change.undo(in: services) }
        }
    }

    private func goBack() {
        if !path.isEmpty { path.removeLast() }
    }

    /// Opens a look: beside the grid in a wide layout; otherwise pushed, or back to it when the
    /// screen under this one is that look.
    private func openLook(_ id: Look.ID) {
        if layout.showsDetailBeside, path.isEmpty {
            show(.look(id))
        } else if path.count >= 2, path[path.count - 2] == .look(id) {
            path.removeLast()
        } else {
            path.append(.look(id))
        }
    }

    /// Opens a picture: beside the grid in a wide layout; otherwise pushed, or back to it when
    /// the screen under this one is that picture.
    private func openPicture(_ id: TryOnPicture.ID) {
        if layout.showsDetailBeside, path.isEmpty {
            show(.picture(id))
        } else if path.count >= 2, path[path.count - 2] == .picture(id) {
            path.removeLast()
        } else {
            path.append(.picture(id))
        }
    }

    /// Delete picture: back to where she came from, with Undo in a toast and, on the Pictures
    /// tab, on a line over the pictures.
    private func pictureDeleted(_ removal: PictureRemoval) {
        if case .picture(let id) = path.last, id == removal.picture.id {
            path.removeLast()
        }
        if besidePicture == removal.picture.id {
            besidePicture = nil
        }
        model.lastPictureRemoval = removal
        reload()
        toast = NookToastMessage(
            TryOnText.deleted, systemImage: "trash", actionTitle: YourLooksText.undo, action: undoPictureDelete)
    }

    private func undoPictureDelete() {
        toast = nil
        Task {
            await model.undoLastPictureRemoval(using: services)
            changes += 1
        }
    }

    /// Delete look: back to the grid, with Undo in a toast and on a line over the looks, which
    /// stays until she leaves the tab, since a toast is easy to miss.
    private func lookDeleted(_ removal: SavedLookRemoval) {
        if case .look(let id) = path.last, id == removal.look.id {
            path.removeLast()
        }
        if besideLook == removal.look.id {
            besideLook = nil
        }
        model.lastRemoval = removal
        reload()
        toast = NookToastMessage(
            LookDetailText.deleted(removal), systemImage: "trash", actionTitle: YourLooksText.undo,
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
