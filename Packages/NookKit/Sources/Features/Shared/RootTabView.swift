import DesignSystem
import Models
import SwiftUI

/// The tab bar with Home, Closet and Saved Looks, and the quick tour over it.
///
/// `AppRootView` builds a new one each time the app opens on a set of services (Phase 17): after
/// onboarding, and on a relaunch. Delete my data goes back to onboarding, so every screen, every
/// cache and every unsent note from before is gone; nothing can show on a screen that was already
/// open.
struct RootTabView: View {
    private let services: NookServices
    /// The quick tours (Phase 16a). The root keeps it across onboarding and Delete my data, so the
    /// `-tour` flag applies once per launch.
    private let tours: TourCenter

    init(services: NookServices, tours: TourCenter) {
        self.services = services
        self.tours = tours
    }

    var body: some View {
        RootTabs(services: services)
            // While a tour shows, VoiceOver reads only the tour, over every tab and the tab bar.
            // A tour on a sheet is modal on its sheet, and the tabs are under the sheet.
            .accessibilityHidden(tours.isShowing && !tours.isShowingInSheet)
            .overlay { TourOverlay(tours: tours) }
            // Every styled sheet draws a tour that's on a sheet over itself (Stage A audit).
            .environment(
                \.nookSheetOverlay, NookSheetOverlay { [tours] in AnyView(TourOverlay(tours: tours, inSheet: true)) })
    }
}

/// The tab bar and the state every tab shares. Built new each time the app opens on services.
private struct RootTabs: View {
    @State private var selection: AppTab = .home
    /// Home's navigation, kept here so App tours can open a screen on it (Phase 16b).
    @State private var homePath: [HomeDestination] = []
    /// Saved Looks' navigation, kept here so a frame on the Home shelf can open a look in it.
    @State private var savedLooksPath: [SavedLooksDestination] = []
    /// Closet's navigation, kept here so Home's suitcase and hamper can open Suitcases and
    /// Laundry in it (Phase 13).
    @State private var closetPath: [ClosetDestination] = []
    private let services: NookServices
    /// Garment pictures, shared by every screen so they're cached once.
    @State private var garmentImages: GarmentImageLoader?
    /// Garment stickers, made once and shared by every screen (Phase 8b).
    @State private var stickers = StickerCache()
    /// A Send feedback note she hasn't sent yet, kept while she moves around the app (Phase 14b),
    /// and since Phase 21a in `services.feedbackDrafts` too, so it's there after a relaunch.
    @State private var feedback: FeedbackModel
    /// The window's real width class, read above the tab view. The tab view itself is told the
    /// width is compact so it puts its bar at the bottom on iPad (RD-01.6), and every tab gets
    /// the real class back (`windowSizeClass(_:)`).
    @Environment(\.horizontalSizeClass) private var windowSizeClass
    /// 27c: whether the app is in front, for the jobs' banner or notification, and to pick up
    /// jobs again when she comes back.
    @Environment(\.scenePhase) private var scenePhase

    init(services: NookServices) {
        self.services = services
        _garmentImages = State(initialValue: GarmentImageLoader(provider: services.images))
        _feedback = State(initialValue: FeedbackModel(services: services))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                // The wardrobe and the shelf in the room switch tabs; a frame on the shelf opens
                // its look on Saved Looks.
                HomeScreen(openTab: { selection = $0 }, openLook: openSavedLook, path: $homePath)
                    .windowSizeClass(windowSizeClass)
            }
            // 27c: a dot while outfit ideas she hasn't seen are ready. Style Me lives on Home.
            .badge(services.aiJobs.unseenResults(.styling) > 0 ? Text(verbatim: "") : nil)
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
        // The note she left unsent before the app last closed (Phase 21a).
        .task { await feedback.restore() }
        // 27c: a finished job's banner, over every tab.
        .overlay(alignment: .top) {
            AIJobBanner(jobs: services.aiJobs, open: openJob)
        }
        // 27c: jobs kept from before carry on, with their own keys.
        .task { await services.aiJobs.resume(with: services) }
        .onChange(of: scenePhase) { _, phase in
            services.aiJobs.isInForeground = phase == .active
            if phase == .active { Task { await services.aiJobs.resume(with: services) } }
        }
        .onChange(of: services.aiJobs.openRequest) { _, id in
            guard let id else { return }
            services.aiJobs.didOpen()
            if let job = services.aiJobs.job(id) { openJob(job) }
        }
    }

    /// 27c: opens a finished job's result: Your looks for a styling job, on Home where Style Me
    /// lives. A job with no screen yet (Ask stylist, try-on) only hides the banner.
    private func openJob(_ job: AIJob) {
        services.aiJobs.dismissAnnouncement()
        guard case .styling(let context, _) = job.request else { return }
        show(.home, home: [.yourLooks(context.request)])
    }

    /// Replay from App tours (Phase 16b): opens the tour's screen, where it starts from step 1
    /// (`TourCenter.replay`). A screen about one thing opens on her first one: the first piece
    /// in Closet, her first look, picture or suitcase. With none yet, or for a screen that needs
    /// her to act first (Your looks, Swap a piece, Try it on), it opens the screen before it, and
    /// the tour starts when she gets there. Profile opens its own screens.
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
            case .editPiece:
                // Her first piece, open in Edit.
                let closet = ClosetModel()
                await closet.load(from: services)
                show(
                    .closet,
                    closet: closet.shown.first.map {
                        [.garment($0.id, name: $0.name), .editPiece($0.id, name: $0.name)]
                    } ?? [])
            case .recentlyDeleted:
                show(.closet, closet: [.recentlyDeleted])
            case .allSuitcases:
                show(.closet, closet: [.suitcases, .allSuitcases])
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
            case .look, .swap, .tryOn:
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
    RootTabView(services: .unavailable, tours: TourCenter(store: nil))
}
