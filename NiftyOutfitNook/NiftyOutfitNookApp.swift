import Features
import Fixtures
import Services
import SwiftUI

#if DEBUG
    import DesignSystem
#endif

@main
struct NiftyOutfitNookApp: App {
    /// What the root needs at launch (Phase 17): the onboarding state and tour progress kept
    /// across launches, and the sample data for the closet she chose.
    private let launch = Self.makeLaunch(arguments: ProcessInfo.processInfo.arguments)

    #if DEBUG
        init() {
            // `-animations off` (debug builds only) turns UIKit's animations off: pushes, sheets
            // and alerts appear at once. Most UI tests pass it, so they don't wait for each
            // transition to finish, or tap while one is still moving.
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "-animations"), arguments.indices.contains(flag + 1),
                arguments[flag + 1] == "off"
            {
                UIView.setAnimationsEnabled(false)
            }
        }
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                // `-catalog` opens the component catalog instead of the app (debug builds only), and
                // `-catalog-page <id>` shows one of its pages alone.
                if ProcessInfo.processInfo.arguments.contains("-catalog") {
                    NookCatalogView(
                        extraPages: [
                            LookBundleCatalog.page(
                                sampleGarments: SamplePhotoGarments.garments(now: .now), images: SamplePhotoProvider())
                        ],
                        onlyPage: NookCatalogView.onlyPage(in: ProcessInfo.processInfo.arguments))
                } else if ProcessInfo.processInfo.arguments.contains("-cutout-bench") {
                    // `-cutout-bench` opens the cutout benchmark (Phase 8a, debug builds only).
                    CutoutBenchScreen(
                        makeService: { VisionCutoutService(options: .init(maxPixelSize: $0)) },
                        samples: {
                            // Drawn at an iPhone 12 photo's size, 3,024 x 4,032.
                            SyntheticGarmentPhotos.Scene.allCases.map {
                                ($0.rawValue, SyntheticGarmentPhotos.jpeg($0, width: 3024, height: 4032))
                            }
                        }
                    )
                } else {
                    AppRootView(launch: launch)
                }
            #else
                AppRootView(launch: launch)
            #endif
        }
    }

    /// Stage A runs on sample data. `-fixtures <set>[:<behavior>]` picks it, for example
    /// `-fixtures large` or `-fixtures demo:offline`; the default is the demo closet, which is
    /// also the sample closet onboarding offers.
    ///
    /// The onboarding state, the tours seen, the name on the sign and the Style Me settings are
    /// kept in the app's own `UserDefaults` suite (`AppStateDefaults`); everything else is in
    /// memory. See `docs/onboarding.md`.
    private static func makeLaunch(arguments: [String]) -> AppLaunch {
        let configuration = FixtureConfiguration(launchArguments: arguments)
        let onboarding = DefaultsOnboardingStore()
        let tours = DefaultsTourProgressStore()
        let profileSettings = DefaultsProfileSettingsKeeper()
        #if DEBUG
            // `-onboarding reset|skip` (Phase 17) and `-tour home|reset|off` (Phase 16a), debug
            // builds only.
            let onboardingOptions = OnboardingLaunchOptions(launchArguments: arguments)
            let tourOptions = TourLaunchOptions(launchArguments: arguments)
        #else
            let onboardingOptions = OnboardingLaunchOptions.standard
            let tourOptions = TourLaunchOptions.standard
        #endif
        return AppLaunch(
            onboarding: onboarding,
            tours: tours,
            profileSettings: profileSettings,
            services: { closet in
                // `-onboarding skip` (`closet` is nil) opens the sample data as it is and writes
                // nothing, so the UI tests start from the same profile every time.
                FixtureServices.make(
                    configuration, startingCloset: closet, tours: tours, onboarding: onboarding,
                    profileSettings: closet == nil ? nil : profileSettings)
            },
            onboardingOptions: onboardingOptions,
            tourOptions: tourOptions)
    }
}
