import Features
import Fixtures
import SwiftUI

#if DEBUG
    import DesignSystem
#endif

@main
struct NiftyOutfitNookApp: App {
    /// Chosen with `-fixtures demo|empty|large`. Not used yet; Phase 3 wires the sets in.
    private let fixtureSet = FixtureSet(launchArguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                // `-catalog` opens the component catalog instead of the app (debug builds only).
                if ProcessInfo.processInfo.arguments.contains("-catalog") {
                    NookCatalogView()
                } else {
                    RootTabView()
                }
            #else
                RootTabView()
            #endif
        }
    }
}
