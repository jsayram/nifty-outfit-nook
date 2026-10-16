import Models
import SwiftUI

/// What the screens a `ClosetDestination` opens report back to the tab that pushed them.
struct ClosetDestinationActions {
    /// Pushes another closet screen on the same stack.
    let open: (ClosetDestination) -> Void
    /// Pops the top screen.
    let back: () -> Void
    /// Remove from closet on garment detail.
    let pieceRemoved: (GarmentRemoval) -> Void
    /// Add a piece or Edit saved.
    let pieceSaved: (GarmentEditorModel.Saved) -> Void
    /// Delete suitcase on a suitcase's detail.
    let suitcaseDeleted: (SuitcaseChange) -> Void

    var styleMeRoutes: StyleMeRoutes {
        StyleMeRoutes(
            addPiece: { open(.addPiece(.photo)) },
            openSuitcases: { open(.suitcases) },
            openSuitcase: { id, name in open(.suitcase(id, name: name)) })
    }
}

/// The screen for a `ClosetDestination`, wherever it's pushed: on Closet, and on Saved Looks
/// from a look's piece. Both tabs use this one view, so a destination added later can't open a
/// placeholder on one of them. The switch has no `default`, so the compiler asks for every case.
struct ClosetDestinationScreen: View {
    let destination: ClosetDestination
    let actions: ClosetDestinationActions
    /// Bumped after Undo on a deleted suitcase, so Suitcases reads its list again.
    var suitcaseChanges = 0

    var body: some View {
        switch destination {
        case .garment(let id, let name):
            GarmentDetailScreen(
                garmentID: id, name: name, open: actions.open, back: actions.back, removed: actions.pieceRemoved)
        case .addPiece(let start):
            GarmentEditorScreen(
                target: .newPiece, firstStep: start == .words ? .words : .choose, resumesDraft: start == .resume,
                saved: actions.pieceSaved, close: actions.back)
        case .editPiece(let id, _, let resumesDraft):
            GarmentEditorScreen(
                target: .garment(id), resumesDraft: resumesDraft, saved: actions.pieceSaved, close: actions.back)
        case .suitcases:
            SuitcasesScreen(open: actions.open, changes: suitcaseChanges)
        case .allSuitcases:
            AllSuitcasesScreen(open: actions.open)
        case .suitcase(let id, let name, let startsPacking):
            SuitcaseDetailScreen(
                suitcaseID: id, name: name, startsPacking: startsPacking, open: actions.open, back: actions.back,
                deleted: actions.suitcaseDeleted)
        case .laundry:
            LaundryScreen(open: actions.open)
        case .recentlyDeleted:
            RecentlyDeletedScreen()
        case .styleMe(let id, _):
            StyleMeScreen(startingPieceID: id, routes: actions.styleMeRoutes)
        case .styleMeFrom(let source):
            StyleMeScreen(source: source, routes: actions.styleMeRoutes)
        case .makeYourOwnLook(let id, _):
            LookBuilderScreen(startingPieceID: id)
        case .profile:
            ProfileScreen()
        }
    }
}
