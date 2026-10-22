import Foundation

/// The one switch for the iPad snapshot tests.
///
/// iPad testing is paused until the app's features are done (22 October 2026): the iPhone 12 is
/// Lily's phone and the main target, and the iPad comes at the end, as UI work. The iPad snapshot
/// tests and their reference images stay in the repo, and they skip themselves unless
/// `NOOK_IPAD_SNAPSHOTS=1` is set. `scripts/test.sh` passes that on to the tests (xcodebuild only
/// forwards variables that start with `TEST_RUNNER_`), and the CI workflow sets it for a manual run
/// with `include_ipad` on. In Xcode, add `NOOK_IPAD_SNAPSHOTS` = `1` to the scheme's test
/// environment variables.
///
/// Apply it with `.ipadSnapshots` on a suite or a test (the trait is in each test target's
/// Support folder), so every iPad snapshot case is found by that one name.
public enum IPadSnapshots {
    public static let isOn: Bool = ProcessInfo.processInfo.environment["NOOK_IPAD_SNAPSHOTS"] == "1"
}
