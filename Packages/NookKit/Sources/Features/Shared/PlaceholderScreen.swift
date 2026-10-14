import SwiftUI

/// A stand-in screen for a tab whose real content comes in a later phase.
struct PlaceholderScreen: View {
    let tab: AppTab
    /// An optional line under the description, such as how much sample data loaded.
    var detail: Text?

    var body: some View {
        ContentUnavailableView {
            Label(tab.title, systemImage: tab.systemImage)
        } description: {
            Text("This part of the app is still being built.", bundle: .module)
        } actions: {
            if let detail {
                detail
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("placeholder.\(tab.rawValue).detail")
            }
        }
        .accessibilityIdentifier("placeholder.\(tab.rawValue)")
    }
}

#Preview {
    PlaceholderScreen(tab: .home)
}
