import XCTest

/// The debug cutout benchmark (`-cutout-bench`, Phase 8a). On the simulator Vision can't lift
/// subjects, so each sample should say so plainly; on a device each one is measured.
///
/// Merges to develop and main and nightly only: this is a developer screen, not something a user
/// reaches, and on the simulator it only checks that nine drawn samples report "unsupported". The
/// benchmark's logic is `CutoutBenchTests` in FeaturesTests and `CutoutFixtureTests`.
final class CutoutBenchTests: XCTestCase {
    override func setUpWithError() throws {
        try skipOnPullRequests("A developer screen; its logic is package-tested.")
        continueAfterFailure = false
    }

    @MainActor
    func testTheBenchmarkRunsTheDrawnSamples() {
        let app = XCUIApplication()
        app.launchArguments = ["-cutout-bench"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Cutout benchmark"].waitUntilExists(timeout: uiTestWait))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The benchmark replaces the app's tabs")
        XCTAssertTrue(app.buttons["Choose photos"].exists)

        // The samples start loading: the count of photos done shows nine, or the button is off
        // while they load and run.
        let samples = app.buttons["cutoutBench.samples"]
        let nine = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " of 9")).firstMatch
        samples.tapUntil(timeout: uiTestWait, else: "The drawn samples didn't start") {
            nine.exists || (samples.exists && !samples.isEnabled)
        }

        // Nine drawn samples. Drawing them at full photo size takes a few seconds here, and once
        // took more than 90 on a busy CI runner.
        XCTAssertTrue(app.staticTexts["9 of 9"].waitUntilExists(timeout: 180))
        XCTAssertTrue(app.staticTexts["Results at 1536 px"].exists)

        let export = app.buttons["Export results"].firstMatch
        app.scrollUntilHittable(export, up: 10)
        XCTAssertTrue(export.isHittable)

        // Each sample says how it went: unsupported here, measured on a device.
        let unsupported = app.staticTexts["Subject lifting isn't supported here (the simulator can't run it)."]
            .firstMatch
        let measured = app.staticTexts["Usable as a sticker?"].firstMatch
        for _ in 0..<10 {
            if unsupported.exists || measured.exists { break }
            app.dragPage(up: true)
        }
        XCTAssertTrue(unsupported.exists || measured.exists)
    }
}
