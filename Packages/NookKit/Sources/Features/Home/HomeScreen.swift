import DesignSystem
import Models
import SwiftUI

/// Home: the illustrated bedroom, where each piece of furniture opens part of the app (RD-01).
///
/// The wardrobe and the shelf switch to the Closet and Saved Looks tabs, and a saved look in a
/// frame under the shelf opens on Saved Looks. The suitcase and the hamper open Suitcases and
/// Laundry on the Closet tab (Phase 13). Everything else is
/// pushed here: Style Me from the laptop and the calendar, Help, Send feedback and Privacy and terms from the desk drawers, and
/// Profile from the name sign and the top-right button. While laundry tracking is off, the
/// hamper opens a short sheet about it instead (RD-11).
struct HomeScreen: View {
    /// Switches the tab bar to another tab.
    let openTab: (AppTab) -> Void
    /// Opens a saved look on Saved Looks, from its frame under the shelf (Phase 12a).
    var openLook: (Look.ID) -> Void = { _ in }
    /// Said once in a toast when Home opens, after Delete my data (Phase 14b).
    var notice: String?

    @Environment(\.services) private var services
    @Environment(\.openInCloset) private var openInCloset
    @State private var model = HomeModel()
    @State private var path: [HomeDestination] = []
    @State private var sheet: HomeSheet?
    @State private var toast: NookToastMessage?
    @State private var noticeShown = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var layout: HomeLayout {
        HomeLayout(dynamicTypeSize: dynamicTypeSize, verticalSizeClass: verticalSizeClass)
    }

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationTitle(Text("Home", bundle: .module, comment: "Navigation title on Home"))
                .navigationBarTitleDisplayMode(.inline)
                // Sideways, the bar would take a third of the screen; the title and Profile move
                // into the controls column instead.
                .toolbar(layout == .sideways ? .hidden : .automatic, for: .navigationBar)
                .toolbar {
                    if layout != .sideways {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                path.append(.profile)
                            } label: {
                                Label {
                                    Text("Profile", bundle: .module, comment: "Button: opens Profile")
                                } icon: {
                                    Image(systemName: "person.crop.circle")
                                }
                            }
                            .accessibilityIdentifier("home.profile")
                        }
                    }
                }
                .navigationDestination(for: HomeDestination.self) { destination in
                    switch destination {
                    case .styleMe(let choosingOccasion):
                        StyleMeScreen(
                            choosingOccasion: choosingOccasion,
                            routes: StyleMeRoutes(
                                addPiece: { path.append(.addPiece) },
                                openSuitcases: { openInCloset([.suitcases]) },
                                openSuitcase: { id, name in openInCloset([.suitcases, .suitcase(id, name: name)]) }))
                    case .addPiece:
                        // From Style Me's empty closet. Saving goes back to Style Me, which reloads.
                        GarmentEditorScreen(target: .newPiece, saved: { _ in goBack() }, close: goBack)
                    case .profile:
                        // A new name shows on the sign as soon as Profile closes: Home reloads
                        // when its path gets shorter (RD-03.1).
                        ProfileScreen()
                    // The desk drawers (RD-10, Phase 14b). The same screens open from Profile.
                    case .help: HelpScreen()
                    case .feedback: FeedbackScreen()
                    case .privacy: PrivacyScreen()
                    }
                }
                .nookSheet(item: $sheet, title: { $0.title }, subtitle: { $0.subtitle }) { sheet in
                    switch sheet {
                    case .laundryTracking:
                        LaundryTrackingSheet(keptDirtyCount: model.keptDirtyCount) {
                            await turnOnLaundryTracking()
                        } openProfile: {
                            self.sheet = nil
                            path.append(.profile)
                        }
                    }
                }
                .nookToast($toast)
        }
        // Each time the tab appears, so a change made on another tab shows: a new source, pieces
        // marked clean in Laundry (Phase 13).
        .task {
            await model.load(from: services)
            if let notice, !noticeShown {
                noticeShown = true
                toast = NookToastMessage(notice, systemImage: "checkmark")
            }
        }
        .onChange(of: path) { old, new in
            // Back from a pushed screen: Style Me may have changed the source or the occasion.
            if new.count < old.count { Task { await model.load(from: services) } }
        }
    }

    /// The room, the large-text rows or the sideways room (`HomeLayout`). Each draws the same
    /// content and opens the same places, so turning the phone or changing the text size keeps
    /// whatever is open.
    @ViewBuilder
    private var home: some View {
        switch layout {
        case .room:
            HomeRoomView(content: model.content, open: open, openLook: openLook)
                .overlay(alignment: .bottom) {
                    errorBanner
                        .padding(.horizontal, NookSpacing.screenMargin)
                        .padding(.bottom, NookSpacing.small)
                }
        case .largeText:
            HomeLargeTextView(content: model.content, open: open) {
                errorBanner.padding(.top, 14)
            }
        case .sideways:
            HomeSidewaysView(
                content: model.content, open: open, openProfile: { path.append(.profile) },
                notice: { errorBanner })
        }
    }

    private func turnOnLaundryTracking() async -> Bool {
        let saved = await model.turnOnLaundryTracking(using: services)
        if saved {
            toast = NookToastMessage(
                String(localized: "Laundry tracking is on.", bundle: .module, comment: "Toast after turning it on"),
                systemImage: "basket")
        }
        return saved
    }

    @ViewBuilder
    private var errorBanner: some View {
        if model.phase == .failed {
            NookBanner(
                String(
                    localized: "Part of your room didn’t load. Everything still opens.", bundle: .module,
                    comment: "Home banner when a store failed"),
                systemImage: "exclamationmark.triangle",
                actionTitle: String(localized: "Try again", bundle: .module, comment: "Button on the Home banner"),
                action: { Task { await model.load(from: services) } }
            )
        }
    }

    private func goBack() {
        if !path.isEmpty { path.removeLast() }
    }

    private func open(_ control: RoomControl) {
        switch control.route(hamper: model.content.hamper) {
        case .tab(let tab): openTab(tab)
        case .closet(let destination): openInCloset([destination])
        case .push(let destination): path.append(destination)
        case .sheet(let sheet): self.sheet = sheet
        }
    }
}

/// The room sized to the screen: it fills the space between the bars and runs under them, and
/// scrolls only on a phone too short to show it at a size with 44 pt targets.
struct HomeRoomView: View {
    let content: HomeRoomContent
    let open: (RoomControl) -> Void
    var openLook: (Look.ID) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let layout = RoomLayout(
                size: CGSize(
                    width: proxy.size.width + insets.leading + insets.trailing,
                    height: proxy.size.height + insets.top + insets.bottom
                ),
                insets: EdgeInsets(top: insets.top, leading: 0, bottom: insets.bottom, trailing: 0)
            )
            ScrollView(.vertical) {
                RoomCanvas(layout: layout, content: content, open: open, openLook: openLook)
            }
            .scrollDisabled(!layout.scrolls)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea()
        }
        .background(Color.nook.background)
    }
}

#Preview {
    RootTabView(services: nil)
}
