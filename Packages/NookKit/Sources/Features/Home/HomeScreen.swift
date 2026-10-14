import DesignSystem
import Models
import SwiftUI

/// Home: the illustrated bedroom, where each piece of furniture opens part of the app (RD-01).
///
/// The wardrobe and the shelf switch to the Closet and Saved Looks tabs. Everything else is
/// pushed here: Style Me from the laptop and the calendar, Suitcases from the suitcase, Laundry
/// from the hamper, Help, Send feedback and Privacy and terms from the desk drawers, and
/// Profile from the name sign and the top-right button.
struct HomeScreen: View {
    /// Switches the tab bar to another tab.
    let openTab: (AppTab) -> Void

    @Environment(\.services) private var services
    @State private var model = HomeModel()
    @State private var path: [HomeDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeRoomView(content: model.content, open: open)
                .overlay(alignment: .bottom) { errorBanner }
                .navigationTitle(Text("Home", bundle: .module, comment: "Navigation title on Home"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
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
                .navigationDestination(for: HomeDestination.self) { destination in
                    HomeStubScreen(destination: destination)
                }
        }
        .task { await model.load(from: services) }
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
            .padding(.horizontal, NookSpacing.screenMargin)
            .padding(.bottom, NookSpacing.small)
        }
    }

    private func open(_ control: RoomControl) {
        switch control.route(hamper: model.content.hamper) {
        case .tab(let tab): openTab(tab)
        case .push(let destination): path.append(destination)
        }
    }
}

/// The room sized to the screen: it fills the space between the bars and runs under them, and
/// scrolls only on a phone too short to show it at a size with 44 pt targets.
struct HomeRoomView: View {
    let content: HomeRoomContent
    let open: (RoomControl) -> Void

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
                RoomCanvas(layout: layout, content: content, open: open)
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
