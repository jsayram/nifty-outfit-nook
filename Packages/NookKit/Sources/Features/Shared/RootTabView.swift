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
    /// The quick tours (Phase 16a). Kept across a fresh start, so the `-tour` flag applies once
    /// per launch; Delete my data erases what it has recorded.
    @State private var tours: TourCenter

    /// - Parameters:
    ///   - services: what every screen below reads its data from.
    ///   - tourLaunch: what the `-tour` debug flag asks of the tours. Release builds pass
    ///     `standard`.
    public init(services: NookServices?, tourLaunch: TourLaunchOptions = .standard) {
        self.services = services
        _tours = State(initialValue: TourCenter(store: services?.tours, launch: tourLaunch))
    }

    public var body: some View {
        RootTabs(services: services, notice: freshStartNotice)
            .id(generation)
            // While a tour shows, VoiceOver reads only the tour, over every tab and the tab bar.
            .accessibilityHidden(tours.isShowing)
            .overlay { TourOverlay(tours: tours) }
            .environment(\.dataDeleted, DataDeletedAction { startFresh() })
            .environment(\.tourCenter, tours)
    }

    private func startFresh() {
        freshStartNotice = String(
            localized: "Your data is deleted. The app is starting fresh.", bundle: .module,
            comment: "Toast on Home after Delete my data")
        // As on a fresh install, Home's tour can start again.
        tours.forgetSession()
        generation += 1
    }
}

/// The tab bar and the state every tab shares. Rebuilt from scratch after Delete my data.
private struct RootTabs: View {
    @State private var selection: AppTab = .home
    /// Home's navigation, kept here so App tours can open a screen on it (Phase 16b).
    @State private var homePath: [HomeDestination] = []
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
    /// The window's real width class, read above the tab view. The tab view itself is told the
    /// width is compact so it puts its bar at the bottom on iPad (RD-01.6), and every tab gets
    /// the real class back (`windowSizeClass(_:)`).
    @Environment(\.horizontalSizeClass) private var windowSizeClass

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
                HomeScreen(openTab: { selection = $0 }, openLook: openSavedLook, notice: notice, path: $homePath)
                    .windowSizeClass(windowSizeClass)
            }
            Tab(AppTab.closet.title, systemImage: AppTab.closet.systemImage, value: AppTab.closet) {
                ClosetScreen(path: $closetPath)
                    .windowSizeClass(windowSizeClass)
            }
            Tab(AppTab.savedLooks.title, systemImage: AppTab.savedLooks.systemImage, value: AppTab.savedLooks) {
                SavedLooksScreen(path: $savedLooksPath)
                    .windowSizeClass(windowSizeClass)
            }
        }
        .tint(.nook.accent)
        // iPadOS 26 puts a tab view's bar at the top of a regular-width window, and SwiftUI has
        // no style that keeps it at the bottom (`.tabBarOnly` still floats it at the top). The tab
        // view draws the bottom bar whenever its width class is compact, so it's told that here;
        // the tabs' contents get the real class back above. See docs/ipad.md.
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.openInSavedLooks, OpenInSavedLooksAction { path in openInSavedLooks(path) })
        .environment(\.openInCloset, OpenInClosetAction { path in openInCloset(path) })
        .environment(\.openForTour, OpenForTourAction { tour in openForTour(tour) })
        .environment(\.services, services)
        .environment(\.garmentImages, garmentImages)
        .environment(\.stickerCache, stickers)
        .environment(\.feedbackDraft, feedback)
    }

    /// Replay from App tours (Phase 16b): opens the tour's screen, where it starts from step 1
    /// (`TourCenter.replay`). A screen about one thing opens on her first one: the first piece
    /// in Closet, her first look, picture or suitcase. With none yet, or for a screen that needs
    /// her to act first (Your looks, Swap a piece), it opens the screen before it, and the tour
    /// starts when she gets there. Profile opens its own screens.
    private func openForTour(_ tour: TourID) {
        Task {
            switch tour {
            case .home:
                show(.home, home: [])
            case .styleMe, .yourLooks:
                show(.home, home: [.styleMe(choosingOccasion: false)])
            case .closet:
                show(.closet, closet: [])
            case .garment:
                let closet = ClosetModel()
                await closet.load(from: services)
                show(.closet, closet: closet.shown.first.map { [.garment($0.id, name: $0.name)] } ?? [])
            case .addPiece:
                show(.closet, closet: [.addPiece(.photo)])
            case .suitcases:
                show(.closet, closet: [.suitcases])
            case .suitcase:
                let suitcases = SuitcasesModel()
                await suitcases.load(from: services)
                show(
                    .closet,
                    closet: [.suitcases] + (suitcases.favorites.first.map { [.suitcase($0.id, name: $0.name)] } ?? []))
            case .laundry, .laundryOff:
                show(.closet, closet: [.laundry])
            case .savedLooks:
                show(.savedLooks, savedLooks: [])
            case .look, .swap:
                let looks = SavedLooksModel()
                await looks.load(from: services)
                show(.savedLooks, savedLooks: looks.items.first.map { [.look($0.id)] } ?? [])
            case .picture:
                let looks = SavedLooksModel()
                await looks.load(from: services)
                show(.savedLooks, savedLooks: looks.pictureItems.first.map { [.picture($0.id)] } ?? [])
            case .lookBuilder:
                show(.savedLooks, savedLooks: [.makeYourOwnLook])
            default:
                break
            }
        }
    }

    /// Selects a tab with its screens open.
    private func show(
        _ tab: AppTab, home: [HomeDestination]? = nil, closet: [ClosetDestination]? = nil,
        savedLooks: [SavedLooksDestination]? = nil
    ) {
        if let home { homePath = home }
        if let closet { closetPath = closet }
        if let savedLooks { savedLooksPath = savedLooks }
        selection = tab
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

extension View {
    /// Gives a tab's content the window's real width class, which the tab view hides from it to
    /// keep its bar at the bottom (RD-01.6).
    fileprivate func windowSizeClass(_ sizeClass: UserInterfaceSizeClass?) -> some View {
        environment(\.horizontalSizeClass, sizeClass)
    }
}

#Preview {
    RootTabView(services: nil)
}
