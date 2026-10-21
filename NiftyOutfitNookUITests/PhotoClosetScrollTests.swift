import XCTest

/// Phase 22b's checkpoint: scrolling her own closet of 2,400 pieces, each with a full-size photo
/// and a cutout in the store's photo folder (`-seed-photo-closet`, debug builds only).
///
/// The simulator reports no hitch counts to `XCTOSSignpostMetric`, and this runner's own queries
/// of the screen stall the app's main thread, so the app scrolls the grid and counts its frames
/// itself (`-frame-stats -auto-scroll`): 3 seconds after the grid shows, 20 seconds down at 4,000
/// points a second and 20 back, with a summary in `Library/Caches/frame-stats.json`. This test
/// only opens the closet and waits. Slow on purpose (the first launch writes about 7 GB of
/// photos), so it only runs when asked:
/// `TEST_RUNNER_NOOK_PERFORMANCE=1 scripts/test.sh -only-testing:NiftyOutfitNookUITests/PhotoClosetScrollTests`.
/// Add `TEST_RUNNER_NOOK_THUMBNAILS=off` to read every photo whole instead, for comparison.
/// The numbers from a run are in docs/image-storage.md.
final class PhotoClosetScrollTests: XCTestCase {
    @MainActor
    func testScrollingAClosetOfRealSizedPhotos() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["NOOK_PERFORMANCE"] == "1", "Set TEST_RUNNER_NOOK_PERFORMANCE=1 to measure scrolling.")
        let app = XCUIApplication()
        app.launchArguments = [
            "-animations", "off", "-tour", "off", "-seed-photo-closet", "2400", "-frame-stats", "-auto-scroll",
        ]
        if environment["NOOK_THUMBNAILS"] == "off" { app.launchArguments += ["-thumbnails", "off"] }
        app.launch()
        let closet = app.tabBars.firstMatch.buttons["Closet"]
        // Seeding the closet on the first launch takes a few minutes.
        XCTAssertTrue(closet.waitForExistence(timeout: 1_800))
        closet.tapUntilSelected(timeout: uiTestWait)
        // The app scrolls on its own now; asking about the screen would disturb it.
        sleep(55)
    }
}
