import DesignSystem
import Models
import SwiftUI

/// Closet: browse, search and filter her pieces (RD-13, LR-09, LR-11).
///
/// The title sits on the wall in the page's header, as in `closet.html`, so the navigation bar
/// only carries Add a piece and Profile. Tapping a piece opens its detail (7a), and the row at
/// the bottom opens Recently deleted; Suitcases, Laundry and Add a piece open stand-ins until
/// their phases build them (7b, 13). The closet reloads each time the tab appears and each time
/// a pushed screen closes, so changes made there show up.
///
/// When she removes a piece on its detail, Closet goes back to the grid and shows a toast with
/// Undo (LR-16.1).
struct ClosetScreen: View {
    @Environment(\.services) private var services
    @State private var model = ClosetModel()
    @State private var path: [ClosetDestination] = []
    @State private var toast: NookToastMessage?

    var body: some View {
        NavigationStack(path: $path) {
            ClosetPage(model: model, open: { path.append($0) }, retry: reload)
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
        case .styleMe(_, let name):
            StyleMeStubScreen(startingPiece: name)
        default:
            StubScreen(
                title: destination.title, systemImage: destination.systemImage,
                identifier: destination.identifier)
        }
    }

    private func reload() {
        Task { await model.load(from: services) }
    }

    private func goBack() {
        if !path.isEmpty { path.removeLast() }
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
