import XCTest

/// Scrolling the large closet (2,400 pieces), measured with the system's scroll hitch metric.
///
/// Slow on purpose (five flings, five times), so it only runs when asked:
/// `TEST_RUNNER_NOOK_PERFORMANCE=1 scripts/test.sh -only-testing:NiftyOutfitNookUITests/ClosetScrollPerformanceTests`.
/// The numbers from a run are in docs/closet.md.
final class ClosetScrollPerformanceTests: XCTestCase {
    @MainActor
    func testScrollingTheLargeCloset() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NOOK_PERFORMANCE"] == "1",
            "Set TEST_RUNNER_NOOK_PERFORMANCE=1 to measure scrolling.")
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.toursOff + ["-fixtures", "large"]
        app.launch()
        let closet = app.tabBars.firstMatch.buttons["Closet"]
        XCTAssertTrue(closet.waitForExistence(timeout: 15))
        closet.tap()
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 15))

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            for _ in 0..<5 {
                grid.swipeUp(velocity: .fast)
            }
            stopMeasuring()
            for _ in 0..<5 {
                grid.swipeDown(velocity: .fast)
            }
        }
    }
}
