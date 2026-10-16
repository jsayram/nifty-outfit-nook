import Features
import Fixtures
import SwiftUI

#if DEBUG
    import DesignSystem
    import Services
#endif

@main
struct NiftyOutfitNookApp: App {
    /// Stage A runs on sample data. `-fixtures <set>[:<behavior>]` picks it, for example
    /// `-fixtures large` or `-fixtures demo:offline`; the default is the demo closet.
    private let services = FixtureServices.make(
        FixtureConfiguration(launchArguments: ProcessInfo.processInfo.arguments)
    )

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
                    // `-tour home`, `-tour reset` and `-tour off` (Phase 16a, debug builds only).
                    RootTabView(
                        services: services,
                        tourLaunch: TourLaunchOptions(launchArguments: ProcessInfo.processInfo.arguments))
                }
            #else
                RootTabView(services: services)
            #endif
        }
    }
}
