import XCTest

/// The debug cutout benchmark (`-cutout-bench`, Phase 8a). On the simulator Vision can't lift
/// subjects, so each sample should say so plainly; on a device each one is measured.
final class CutoutBenchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheBenchmarkRunsTheDrawnSamples() {
        let app = XCUIApplication()
        app.launchArguments = ["-cutout-bench"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Cutout benchmark"].waitUntilExists(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The benchmark replaces the app's tabs")
        XCTAssertTrue(app.buttons["Choose photos"].exists)

        app.buttons["cutoutBench.samples"].tap()

        // Nine drawn samples. Drawing them at full photo size takes a few seconds.
        XCTAssertTrue(app.staticTexts["9 of 9"].waitUntilExists(timeout: 90))
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
