import DesignSystem
import SwiftUI

/// A stand-in for a screen whose real content comes in a later phase. It uses the same empty
/// state as the rest of the app, so the path to it can be checked now. UI tests find it by
/// `stub.<identifier>`.
struct StubScreen: View {
    let title: String
    let systemImage: String
    let identifier: String
    var message = String(
        localized: "This part of the app is still being built.", bundle: .module,
        comment: "Shown on a tab whose screen isn't built yet")

    var body: some View {
        ScrollView {
            NookEmptyState(title, message: message, systemImage: systemImage)
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.vertical, NookSpacing.xxxLarge)
                .frame(maxWidth: .infinity)
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("stub.\(identifier)")
    }
}
