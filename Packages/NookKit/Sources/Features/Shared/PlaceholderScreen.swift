import SwiftUI

/// A stand-in screen for a tab whose real content comes in a later phase.
struct PlaceholderScreen: View {
    let tab: AppTab

    var body: some View {
        ContentUnavailableView {
            Label(tab.title, systemImage: tab.systemImage)
        } description: {
            Text("This part of the app is still being built.", bundle: .module)
        }
        .accessibilityIdentifier("placeholder.\(tab.rawValue)")
    }
}

#Preview {
    PlaceholderScreen(tab: .home)
}
