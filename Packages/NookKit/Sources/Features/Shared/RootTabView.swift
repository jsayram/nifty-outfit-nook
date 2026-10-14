import SwiftUI

/// The app's root: a tab bar with Home, Closet and Saved Looks.
public struct RootTabView: View {
    @State private var selection: AppTab = .home

    public init() {}

    public var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                HomeScreen()
            }
            Tab(AppTab.closet.title, systemImage: AppTab.closet.systemImage, value: AppTab.closet) {
                ClosetScreen()
            }
            Tab(AppTab.savedLooks.title, systemImage: AppTab.savedLooks.systemImage, value: AppTab.savedLooks) {
                SavedLooksScreen()
            }
        }
    }
}

#Preview {
    RootTabView()
}
