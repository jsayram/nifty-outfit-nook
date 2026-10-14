import DesignSystem
import Models
import SwiftUI

/// Closet: browse, search and filter her pieces (RD-13, LR-09, LR-11).
///
/// The title sits on the wall in the page's header, as in `closet.html`, so the navigation bar
/// only carries Add a piece and Profile. Tapping a piece opens its detail; Suitcases, Laundry,
/// Recently deleted and Add a piece open stand-ins until their phases build them (7a, 7b, 13).
/// The closet reloads each time the tab appears, so changes made elsewhere show up.
struct ClosetScreen: View {
    @Environment(\.services) private var services
    @State private var model = ClosetModel()
    @State private var path: [ClosetDestination] = []

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
                .navigationDestination(for: ClosetDestination.self) { destination in
                    StubScreen(
                        title: destination.title, systemImage: destination.systemImage,
                        identifier: destination.identifier)
                }
        }
        .task { await model.load(from: services) }
    }

    private func reload() {
        Task { await model.load(from: services) }
    }
}

#Preview {
    RootTabView(services: nil)
}
