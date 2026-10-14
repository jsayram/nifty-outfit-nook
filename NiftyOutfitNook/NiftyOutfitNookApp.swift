import Features
import Fixtures
import SwiftUI

#if DEBUG
    import DesignSystem
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
                // `-catalog` opens the component catalog instead of the app (debug builds only).
                if ProcessInfo.processInfo.arguments.contains("-catalog") {
                    NookCatalogView()
                } else {
                    RootTabView(services: services)
                }
            #else
                RootTabView(services: services)
            #endif
        }
    }
}
