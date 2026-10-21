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
            // `-frame-stats` (debug builds only) measures frames, hitches and memory (Phase 22b).
            if arguments.contains("-frame-stats") {
                FrameStats.shared.start(autoScroll: arguments.contains("-auto-scroll"))
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
                } else if ProcessInfo.processInfo.arguments.contains("-limits-lab") {
                    // `-limits-lab` opens the Phase 24b limits screen (debug builds only).
                    LimitsLabScreen(
                        account: AppGateway.account, paid: AppGateway.paid, controls: AppGateway.limitsControls)
                } else if ProcessInfo.processInfo.arguments.contains("-gateway-lab") {
                    // `-gateway-lab` opens the Phase 24a gateway screen (debug builds only).
                    GatewayLabScreen(
                        account: AppGateway.account, controls: AppGateway.labControls, log: AppGateway.log)
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
        switch NookStorage.open(backups: .app) {
        case .ready(let opened):
            storage = opened
        case .problem(let problem):
            // The recovery screen can still export the raw store, encrypted (Phase 21b).
            return AppLaunch(
                onboarding: InMemoryOnboardingStore(), tours: InMemoryTourProgressStore(),
                services: { _ in FixtureServices.make(FixtureConfiguration(set: .empty)) },
                tourOptions: .standard, offersSampleCloset: offersSampleCloset,
                storeProblem: StoreOpenProblem(problem), storeCopy: StoreCopyExport(location: .app))
        }
        let onboarding = storage.onboarding
        let tours = storage.tours
        // Her photos (Phase 22a), in the folder backups carry. Delete my data removes it with
        // the backups' files (`BackupDataEraser`, in `storage.erasableData`). Their thumbnails
        // and the sweep for files nothing points to came in Phase 22b.
        let photos = PhotoFileStore(directory: (storage.backupLocation ?? .app).photos)
        let imageFiles = storage.imageFiles
        #if DEBUG
            // `-thumbnails off` (debug builds only) reads every photo whole, to measure what the
            // thumbnails save.
            let thumbnails =
                DebugLaunchArgument.value(after: "-thumbnails", in: arguments) == "off" ? nil : imageFiles?.thumbnails
        #else
            let thumbnails = imageFiles?.thumbnails
        #endif
        // Sign-in and the backend (Phase 24a): the fakes until Clerk and Convex are configured.
        // Nothing on the local closet depends on it.
        let account = AppGateway.account
        let paid = AppGateway.paid
        return AppLaunch(
            onboarding: onboarding,
            tours: tours,
            profileSettings: storage.profileSettings,
            services: { closet in
                switch offersSampleCloset ? closet : .empty {
                case .empty:
                    // Her own closet, kept in the store, with Backups (Phase 21b) and her own
                    // photos from the camera and the system picker, kept without their metadata
                    // (Phase 22a). Delete my data also deletes the migration's safety copy, the
                    // backups' files and the photos. The stores are read here, so after a restore
                    // (`reload`) the services get fresh ones.
                    let tours = storage.tours
                    let onboarding = storage.onboarding
                    var services = FixtureServices.make(
                        configuration, startingCloset: .empty, tours: tours, onboarding: onboarding,
                        stores: storage.stores)
                    services.photos = LocalPhotoIntake(files: photos)
                    services.images = StoredPhotoProvider(
                        files: photos, thumbnails: thumbnails, fallback: services.images)
                    if let imageFiles { services.imageFiles = imageFiles }
                    // Her weather choices (Phase 29) are erased with the profile, before onboarding.
                    AppWeather.install(into: &services, arguments: arguments)
                    services.deletion = LocalDataDeletion(
                        stores: storage.erasableData + [
                            (.profile, tours), (.profile, services.weatherSettings), (.profile, onboarding),
                        ])
                    services.backups = storage.backups
                    services.account = account
                    services.paid = paid
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
                    AppWeather.install(into: &services, arguments: arguments, keepsSettings: closet != nil)
                    services.deletion = LocalDataDeletion(
                        stores: storage.erasableData + LocalDataDeletion.stores(of: services))
                    services.account = account
                    services.paid = paid
                    return services
                }
            },
            onboardingOptions: onboardingOptions,
            tourOptions: tourOptions,
            offersSampleCloset: offersSampleCloset,
            // The Stage A `UserDefaults` suite moves into the store once. Then, away from the
            // screens, files nothing points to any more are removed (Phase 22b).
            prepare: {
                AppStateDefaultsImport.run(into: storage.container)
                #if DEBUG
                    await DebugPhotoCloset.seedIfAsked(arguments: arguments, storage: storage, photos: photos)
                #endif
                if let imageFiles {
                    Task.detached(priority: .utility) { await imageFiles.removeUnused() }
                }
            },
            erasedOnReset: storage.erasableData.map(\.1),
            backups: storage.backups,
            reload: { storage.reload() })
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
