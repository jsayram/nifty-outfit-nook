import DesignSystem
import SwiftUI

/// A stand-in for a screen Home opens whose real content comes in a later phase. It uses the
/// same empty state as the rest of the app, so the path from the room can be checked now.
struct HomeStubScreen: View {
    let destination: HomeDestination

    var body: some View {
        ScrollView {
            NookEmptyState(
                destination.title,
                message: String(
                    localized: "This part of the app is still being built.", bundle: .module,
                    comment: "Shown on a tab whose screen isn't built yet"),
                systemImage: destination.systemImage
            )
            .padding(.horizontal, NookSpacing.screenMargin)
            .padding(.vertical, NookSpacing.xxxLarge)
            .frame(maxWidth: .infinity)
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("stub.\(destination.identifier)")
    }
}

#Preview {
    NavigationStack {
        HomeStubScreen(destination: .styleMe(choosingOccasion: false))
    }
}
