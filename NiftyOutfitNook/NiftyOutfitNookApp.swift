import Features
import Fixtures
import Models
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

    /// Her data lives in the store on the iPhone (Phase 21a, `NookStorage`), opened once here,
    /// before anything reads it. If it can't be opened, the app shows why and changes nothing.
    ///
    /// Release builds keep everything in the store, and have no sample data (Phase 20a). Debug
    /// builds run on sample data: `-fixtures <set>[:<behavior>]` picks it, for example
    /// `-fixtures large` or `-fixtures demo:offline`, and the default is the demo closet, which is
    /// also the sample closet onboarding offers. There the sample closet stays in memory and comes
    /// back as it ships at each launch, keeping only the name on the sign and the Style Me
    /// settings; the empty closet keeps everything in the store, as Release does. The onboarding
    /// state and the tours seen are in the store in every build. See `docs/onboarding.md`.
    private static func makeLaunch(arguments: [String]) -> AppLaunch {
        #if DEBUG
            let configuration = FixtureConfiguration(launchArguments: arguments)
            // `-onboarding reset|skip` (Phase 17) and `-tour home|reset|off` (Phase 16a), debug
            // builds only.
            let onboardingOptions = OnboardingLaunchOptions(launchArguments: arguments)
            let tourOptions = TourLaunchOptions(launchArguments: arguments)
            let offersSampleCloset = true
        #else
            // Release builds ship no sample data and read no `-fixtures` argument (Phase 20a).
            let configuration = FixtureConfiguration(set: .empty)
            let onboardingOptions = OnboardingLaunchOptions.standard
            let tourOptions = TourLaunchOptions.standard
            let offersSampleCloset = false
        #endif

        let storage: NookStorage
        switch NookStorage.open() {
        case .ready(let opened):
            storage = opened
        case .problem(let problem):
            return AppLaunch(
                onboarding: InMemoryOnboardingStore(), tours: InMemoryTourProgressStore(),
                services: { _ in FixtureServices.make(FixtureConfiguration(set: .empty)) },
                tourOptions: .standard, offersSampleCloset: offersSampleCloset,
                storeProblem: StoreOpenProblem(problem))
        }
        let onboarding = storage.onboarding
        let tours = storage.tours
        return AppLaunch(
            onboarding: onboarding,
            tours: tours,
            profileSettings: storage.profileSettings,
            services: { closet in
                switch offersSampleCloset ? closet : .empty {
                case .empty:
                    // Her own closet, kept in the store. Delete my data also deletes the
                    // migration's safety copy.
                    var services = FixtureServices.make(
                        configuration, startingCloset: .empty, tours: tours, onboarding: onboarding,
                        stores: storage.stores)
                    services.deletion = LocalDataDeletion(
                        stores: storage.erasableData + [(.profile, tours), (.profile, onboarding)])
                    return services
                case .sample, nil:
                    // The debug sample closet, in memory. `-onboarding skip` (`closet` is nil)
                    // opens it as it is and keeps nothing else, so the UI tests start from the
                    // same profile every time. Delete my data also clears the store, so nothing
                    // from an earlier closet comes back.
                    var services = FixtureServices.make(
                        configuration, startingCloset: closet, tours: tours, onboarding: onboarding,
                        profileSettings: closet == nil ? nil : storage.profileSettings,
                        feedbackDrafts: closet == nil ? nil : storage.feedbackDrafts)
                    services.deletion = LocalDataDeletion(
                        stores: storage.erasableData + LocalDataDeletion.stores(of: services))
                    return services
                }
            },
            onboardingOptions: onboardingOptions,
            tourOptions: tourOptions,
            offersSampleCloset: offersSampleCloset,
            // The Stage A `UserDefaults` suite moves into the store once.
            prepare: { AppStateDefaultsImport.run(into: storage.container) },
            erasedOnReset: storage.erasableData.map(\.1))
    }
}

extension StoreOpenProblem {
    /// The store's problem, for the recovery screen.
    init(_ problem: StoreProblem) {
        switch problem {
        case .newerVersion: self = .newerVersion
        case .notEnoughSpace: self = .notEnoughSpace
        case .updateFailed: self = .updateFailed
        case .couldNotOpen: self = .couldNotOpen
        }
    }
}
