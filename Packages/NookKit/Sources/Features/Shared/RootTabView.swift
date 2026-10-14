import DesignSystem
import Models
import SwiftUI

/// The app's root: a tab bar with Home, Closet and Saved Looks.
public struct RootTabView: View {
    @State private var selection: AppTab = .home
    private let services: NookServices?

    /// - Parameter services: what every screen below reads its data from.
    public init(services: NookServices?) {
        self.services = services
    }

    public var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                // The wardrobe and the shelf in the room switch tabs.
                HomeScreen { selection = $0 }
            }
            Tab(AppTab.closet.title, systemImage: AppTab.closet.systemImage, value: AppTab.closet) {
                ClosetScreen()
            }
            Tab(AppTab.savedLooks.title, systemImage: AppTab.savedLooks.systemImage, value: AppTab.savedLooks) {
                SavedLooksScreen()
            }
        }
        .tint(.nook.accent)
        .environment(\.services, services)
    }
}

#Preview {
    RootTabView(services: nil)
}
