import DesignSystem
import SwiftUI

/// A screen Saved Looks pushes.
nonisolated enum SavedLooksDestination: Hashable, Sendable {
    /// "+ Make your own" (LR-08.3, Phase 11).
    case makeYourOwnLook
}

/// Saved Looks. The tabs, search and look detail come in Phase 12a; until then it says so and
/// offers "+ Make your own" (LR-08.3), which opens Make your own look.
struct SavedLooksScreen: View {
    @State private var path: [SavedLooksDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                NookEmptyState(
                    AppTab.savedLooks.title,
                    message: String(
                        localized: "This part of the app is still being built.", bundle: .module,
                        comment: "Shown on a tab whose screen isn't built yet"),
                    systemImage: AppTab.savedLooks.systemImage
                ) {
                    NookButton(
                        String(
                            localized: "+ Make your own", bundle: .module,
                            comment: "Saved Looks: opens Make your own look (RD-08, LR-08)"),
                        kind: .soft, fillsWidth: true
                    ) {
                        path.append(.makeYourOwnLook)
                    }
                    .accessibilityLabel(
                        Text("Make your own look", bundle: .module, comment: "Spoken label of + Make your own")
                    )
                    .accessibilityIdentifier("savedLooks.makeYourOwn")
                }
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.vertical, NookSpacing.xxxLarge)
                .frame(maxWidth: .infinity)
            }
            .background(Color.nook.wallGradient.ignoresSafeArea())
            .navigationTitle(AppTab.savedLooks.title)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("placeholder.savedLooks")
            .navigationDestination(for: SavedLooksDestination.self) { destination in
                switch destination {
                case .makeYourOwnLook: LookBuilderScreen()
                }
            }
        }
    }
}
