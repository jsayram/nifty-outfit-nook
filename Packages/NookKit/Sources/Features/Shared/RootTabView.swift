import DesignSystem
import Models
import SwiftUI

/// The app's root: a tab bar with Home, Closet and Saved Looks.
public struct RootTabView: View {
    @State private var selection: AppTab = .home
    /// Saved Looks' navigation, kept here so a frame on the Home shelf can open a look in it.
    @State private var savedLooksPath: [SavedLooksDestination] = []
    private let services: NookServices?
    /// Garment pictures, shared by every screen so they're cached once.
    @State private var garmentImages: GarmentImageLoader?
    /// Garment stickers, made once and shared by every screen (Phase 8b).
    @State private var stickers = StickerCache()

    /// - Parameter services: what every screen below reads its data from.
    public init(services: NookServices?) {
        self.services = services
        _garmentImages = State(initialValue: services.map { GarmentImageLoader(provider: $0.images) })
    }

    public var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                // The wardrobe and the shelf in the room switch tabs; a frame on the shelf opens
                // its look on Saved Looks.
                HomeScreen(openTab: { selection = $0 }, openLook: openSavedLook)
            }
            Tab(AppTab.closet.title, systemImage: AppTab.closet.systemImage, value: AppTab.closet) {
                ClosetScreen()
            }
            Tab(AppTab.savedLooks.title, systemImage: AppTab.savedLooks.systemImage, value: AppTab.savedLooks) {
                SavedLooksScreen(path: $savedLooksPath)
            }
        }
        .tint(.nook.accent)
        .environment(\.services, services)
        .environment(\.garmentImages, garmentImages)
        .environment(\.stickerCache, stickers)
    }

    /// Switches to Saved Looks with this look open, on top of the grid.
    private func openSavedLook(_ id: Look.ID) {
        savedLooksPath = [.look(id)]
        selection = .savedLooks
    }
}

#Preview {
    RootTabView(services: nil)
}
