import DesignSystem
import Models
import SwiftUI

/// The app's root (Phase 17): onboarding on a fresh install and after Delete my data, otherwise
/// the tabs. See `AppRootModel` for what it decides and `docs/onboarding.md` for why.
///
/// The quick tours live here, above both, so Home's tour can start the moment onboarding hands
/// over, and the `-tour` flag applies once per launch.
public struct AppRootView: View {
    @State private var model: AppRootModel
    @State private var tours: TourCenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(launch: AppLaunch) {
        _model = State(initialValue: AppRootModel(launch: launch))
        _tours = State(initialValue: TourCenter(store: launch.tours, launch: launch.tourOptions))
    }

    public var body: some View {
        content
            // A short cross-fade between onboarding and the tabs, or none with Reduce Motion.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.screen)
            .task { await model.start() }
            .environment(\.tourCenter, tours)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            // A moment while the app reads whether onboarding was finished.
            Color.nook.background
                .ignoresSafeArea()
        case .onboarding(let notice):
            OnboardingFlow(notice: notice) { await model.finish($0) }
                .id(model.generation)
                .transition(.opacity)
        case .ready(let services):
            RootTabView(services: services, tours: tours)
                .id(model.generation)
                .transition(.opacity)
                .environment(
                    \.dataDeleted,
                    DataDeletedAction {
                        // As on a fresh install, the tours can start again once she's back on Home.
                        tours.forgetSession()
                        model.dataDeleted()
                    })
        }
    }
}
