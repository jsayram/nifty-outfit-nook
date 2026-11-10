import XCTest

/// N4: the debug capture hooks reach states a normal launch only flashes or never shows. `-hold`
/// keeps a loading state on screen and `-fail` makes one operation fail; the package tests cover
/// the flags and the fakes, these check that the running app shows the states.
final class CaptureHooksTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    /// `-hold weather`: Style Me's weather row stays on "Checking the weather…".
    @MainActor
    func testAHeldWeatherReadingStaysOnChecking() {
        let app = launch(["-hold", "weather"])
        let weather = app.buttons["styleMe.weather"]
        app.buttons["home.laptop"].tapUntil(weather, appears: Self.wait)
        XCTAssertTrue(weather.label.contains("Checking the weather"), "Weather row: \(weather.label)")
        // Still checking a moment later: it's held, not slow.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "held")], timeout: 3)
        XCTAssertTrue(weather.label.contains("Checking the weather"), "Weather row: \(weather.label)")
    }

    /// `-fail looks-load`: Saved Looks says its looks didn't load, with Try again.
    @MainActor
    func testAFailedLooksLoadShowsSavedLooksError() {
        let app = launch(["-fail", "looks-load"])
        let title = app.staticTexts["Your saved looks didn’t load"]
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntil(title, appears: Self.wait)
        XCTAssertTrue(app.buttons["Try again"].waitUntilExists(timeout: Self.wait))
    }

    @MainActor
    private func launch(_ hooks: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo"] + hooks
        app.launch()
        XCTAssertTrue(app.buttons["home.laptop"].waitUntilExists(timeout: Self.wait), "Home didn't open")
        return app
    }
}
