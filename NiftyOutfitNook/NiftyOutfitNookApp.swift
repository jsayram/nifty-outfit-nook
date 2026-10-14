import Features
import Fixtures
import SwiftUI

@main
struct NiftyOutfitNookApp: App {
    /// Chosen with `-fixtures demo|empty|large`. Not used yet; Phase 3 wires the sets in.
    private let fixtureSet = FixtureSet(launchArguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
