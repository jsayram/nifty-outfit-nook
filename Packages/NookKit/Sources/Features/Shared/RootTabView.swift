import DesignSystem
import Models
import SwiftUI

/// The app's root: a tab bar with Home, Closet and Saved Looks.
///
/// After Delete my data (Phase 14b) the whole tree below is built again, so every screen, every
/// cache and every unsent note starts empty, and Home is the selected tab with a short note that
/// the data is gone. Nothing from before can show on a screen that was already open.
public struct RootTabView: View {
    private let services: NookServices?
    /// Bumped after Delete my data, which gives the tabs a new identity.
    @State private var generation = 0
    /// What Home says when it opens again after a fresh start.
    @State private var freshStartNotice: String?

    /// - Parameter services: what every screen below reads its data from.
    public init(services: NookServices?) {
        self.services = services
    }

    public var body: some View {
        RootTabs(services: services, notice: freshStartNotice)
            .id(generation)
            .environment(\.dataDeleted, DataDeletedAction { startFresh() })
    }

    private func startFresh() {
        freshStartNotice = String(
            localized: "Your data is deleted. The app is starting fresh.", bundle: .module,
            comment: "Toast on Home after Delete my data")
        generation += 1
    }
}

/// The tab bar and the state every tab shares. Rebuilt from scratch after Delete my data.
private struct RootTabs: View {
    @State private var selection: AppTab = .home
    /// Saved Looks' navigation, kept here so a frame on the Home shelf can open a look in it.
    @State private var savedLooksPath: [SavedLooksDestination] = []
    /// Closet's navigation, kept here so Home's suitcase and hamper can open Suitcases and
    /// Laundry in it (Phase 13).
    @State private var closetPath: [ClosetDestination] = []
    private let services: NookServices?
    /// Shown once on Home when it opens, after Delete my data.
    private let notice: String?
    /// Garment pictures, shared by every screen so they're cached once.
    @State private var garmentImages: GarmentImageLoader?
    /// Garment stickers, made once and shared by every screen (Phase 8b).
    @State private var stickers = StickerCache()
    /// A Send feedback note she hasn't sent yet, kept while she moves around the app (Phase 14b).
    /// In memory only, like every Stage A draft.
    @State private var feedback = FeedbackModel()

    init(services: NookServices?, notice: String?) {
        self.services = services
        self.notice = notice
        _garmentImages = State(initialValue: services.map { GarmentImageLoader(provider: $0.images) })
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                // The wardrobe and the shelf in the room switch tabs; a frame on the shelf opens
                // its look on Saved Looks.
                HomeScreen(openTab: { selection = $0 }, openLook: openSavedLook, notice: notice)
            }
            Tab(AppTab.closet.title, systemImage: AppTab.closet.systemImage, value: AppTab.closet) {
                ClosetScreen(path: $closetPath)
            }
            Tab(AppTab.savedLooks.title, systemImage: AppTab.savedLooks.systemImage, value: AppTab.savedLooks) {
                SavedLooksScreen(path: $savedLooksPath)
            }
        }
        .tint(.nook.accent)
        .environment(\.openInSavedLooks, OpenInSavedLooksAction { path in openInSavedLooks(path) })
        .environment(\.openInCloset, OpenInClosetAction { path in openInCloset(path) })
        .environment(\.services, services)
        .environment(\.garmentImages, garmentImages)
        .environment(\.stickerCache, stickers)
        .environment(\.feedbackDraft, feedback)
    }

    /// Switches to Saved Looks with this look open, on top of the grid.
    private func openSavedLook(_ id: Look.ID) {
        openInSavedLooks([.look(id)])
    }

    /// Switches to Closet with these screens open, on top of the grid.
    private func openInCloset(_ path: [ClosetDestination]) {
        closetPath = path
        selection = .closet
    }

    /// Switches to Saved Looks with these screens open, on top of the grid.
    private func openInSavedLooks(_ path: [SavedLooksDestination]) {
        savedLooksPath = path
        selection = .savedLooks
    }
}

#Preview {
    RootTabView(services: nil)
}
