import Features
import Fixtures
import Models
import Networking
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

    /// Whether the phone is online (Phase 26), for the offline banner where cloud features need it.
    /// Debug builds take `-connection offline` or `-connection online`, which fix the state for UI
    /// tests; otherwise it follows the system's path monitor.
    @State private var connection = ConnectionStatus()
    /// 27c: when she leaves mid-job, the app asks iOS for a short background task.
    @Environment(\.scenePhase) private var scenePhase

    private var connectivitySource: any ConnectivitySource {
        #if DEBUG
            switch DebugLaunchArgument.value(after: "-connection", in: ProcessInfo.processInfo.arguments) {
            case "offline": return FixedConnectivitySource(.offline)
            case "online": return FixedConnectivitySource(.online)
            default: break
            }
        #endif
        return PathConnectivitySource()
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(\.connection, connection)
                #if DEBUG
                    // `-fake-camera` (33b): the try-on photo's camera is a drawn stand-in.
                    .environment(
                        \.tryOnCameraMaker, AppTryOn.cameraMaker(arguments: ProcessInfo.processInfo.arguments) ?? .live)
                #endif
                .task { await connection.follow(connectivitySource) }
                // 30a: the subscription hint on paid requests follows StoreKit.
                .task { await AppSubscriptions.follow() }
                .onAppear { AppJobs.installDelegate() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AppJobs.didEnterBackground() }
        }
    }

    @ViewBuilder private var root: some View {
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
            } else if ProcessInfo.processInfo.arguments.contains("-device-checks") {
                // `-device-checks` opens the device checks screen: file protection, the store and the
                // last migration, and a locked-phone test (debug builds only).
                DeviceChecksScreen(source: .make())
            } else if ProcessInfo.processInfo.arguments.contains("-diagnostics-lab") {
                // `-diagnostics-lab` opens the Phase 31 diagnostics screen (debug builds only).
                DiagnosticsLabScreen(log: AppDiagnostics.log)
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
            // `-migration-kill-at <step>`, `-migration-pause-at <step>` and `-make-old-store` (debug
            // builds only) set up a real migration to kill on a device (checklist 2.16).
            MigrationDebug.install(arguments: arguments)
            MigrationDebug.makeOldStoreIfAsked(arguments: arguments, location: .app)
        #else
            // Release builds ship no sample data and read no `-fixtures` argument (Phase 20a).
            let configuration = FixtureConfiguration(set: .empty)
            let onboardingOptions = OnboardingLaunchOptions.standard
            let tourOptions = TourLaunchOptions.standard
            let offersSampleCloset = false
        #endif

        // Phase 31: Apple's MetricKit crash and speed reports, kept on the phone.
        AppDiagnostics.start()

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
        // 32b (L9): true only in a Release build with no backend settings.
        let cloudUnavailable = AppGateway.cloudUnavailable
        // Release: Clerk, or the fake sign-in in a Debug build. None in a Release build with no
        // backend settings, where the cloud features say they aren't available right now.
        let offersSignIn = !cloudUnavailable
        // The cloud stylist (Phase 27a): with the real backend, or `-cloud-stylist` on the fake.
        let cloudStylist = AppStylist.usesCloud(arguments) ? paid : nil
        // 33a: real try-on pictures, with her face kept on the phone. With the real backend, or
        // `-cloud-tryon` on the fake.
        let cloudTryOn = AppTryOn.usesCloud(arguments) ? paid : nil
        let tryOnAnalyzer = AppTryOn.analyzer(arguments: arguments)
        // 27c: one set of AI jobs for the life of the app: kept in the store for her own closet,
        // in memory for the debug sample closet (which comes back as it ships at each launch).
        let keptJobs = AppJobs.kept(in: storage)
        let sampleJobs = AppJobs.inMemory()
        let jobNotifier = AppJobs.notifier
        // 30a: StoreKit, with its transaction listener started now, at launch.
        let subscriptions = AppSubscriptions.service
        // 30b: picture packs, with their transaction listener started now too.
        let credits = AppSubscriptions.credits
        AppJobs.all = [keptJobs, sampleJobs]
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
                    // Phase 28: Quick ideas, the stylist on the phone, in place of Stage A's stand-in.
                    // A debug launch that asks for a failing or partial stylist keeps the stand-in.
                    if configuration.behavior == .normal { services.stylist = QuickIdeasStylist.standard }
                    // Her weather choices (Phase 29) are erased with the profile, before onboarding.
                    AppWeather.install(into: &services, arguments: arguments)
                    // The cloud stylist (Phase 27a), once the backend is real or a debug launch asks.
                    AppStylist.install(into: &services, paid: cloudStylist)
                    // 33a: try-on pictures, made from her own photo files.
                    AppTryOn.install(into: &services, paid: cloudTryOn, files: photos, analyzer: tryOnAnalyzer)
                    // 33b: the try-on photo is checked on the phone before she saves it.
                    AppTryOn.installPhotoSetup(into: &services, files: photos, analyzer: tryOnAnalyzer)
                    // 27c: AI jobs and Ask stylist conversations, kept in the store.
                    services.aiJobs = keptJobs
                    services.stylistThreads = storage.stylistThreads
                    AppDiagnostics.install(into: &services)
                    // Delete my data, and Delete my account (Phase 24c) when she's signed in. The
                    // jobs stop first, so none writes a look after the looks are gone.
                    services.deletion = AccountDataDeletion(
                        local: LocalDataDeletion(
                            stores: [(.looks, AIJobsEraser(keptJobs))] + storage.erasableData + [
                                (.drafts, AppDiagnostics.log),
                                (.profile, tours), (.profile, services.weatherSettings),
                                (.profile, services.stylistConsent), (.profile, services.tryOnConsent),
                                (.profile, jobNotifier),
                                (.profile, onboarding),
                            ]),
                        account: account)
                    services.backups = storage.backups
                    services.account = account
                    // 32b (L9): a Release build with no backend settings says so; nothing is simulated.
                    services.cloudUnavailable = cloudUnavailable
                    // Release: Sign in with Apple when she first uses a cloud feature (`SignInGate`).
                    services.offersSignIn = offersSignIn
                    services.paid = paid
                    services.subscriptions = subscriptions
                    services.credits = credits
                    AppGateway.installSupport(into: &services)
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
                    AppStylist.install(into: &services, paid: cloudStylist, keepsSettings: closet != nil)
                    AppTryOn.install(
                        into: &services, paid: cloudTryOn, files: photos, analyzer: tryOnAnalyzer,
                        keepsSettings: closet != nil)
                    services.aiJobs = sampleJobs
                    AppDiagnostics.install(into: &services)
                    services.deletion = AccountDataDeletion(
                        local: LocalDataDeletion(
                            stores: [(.looks, AIJobsEraser(sampleJobs))] + storage.erasableData + [
                                (.profile, jobNotifier)
                            ] + LocalDataDeletion.stores(of: services)),
                        account: account)
                    services.account = account
                    // 32b (L9): a Release build with no backend settings says so; nothing is simulated.
                    services.cloudUnavailable = cloudUnavailable
                    // Release: Sign in with Apple when she first uses a cloud feature (`SignInGate`).
                    services.offersSignIn = offersSignIn
                    services.paid = paid
                    services.subscriptions = subscriptions
                    services.credits = credits
                    AppGateway.installSupport(into: &services)
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
                    await AppGateway.signInIfAsked(arguments: arguments)
                    await AppStylist.prepareFakeIfAsked(arguments: arguments)
                    await AppTryOn.seedIfAsked(arguments: arguments, storage: storage, photos: photos)
                    await AppTryOn.prepareFakeIfAsked(arguments: arguments)
                    await AppDiagnostics.seedIfAsked(arguments: arguments)
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
