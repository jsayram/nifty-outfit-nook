import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTheTabBar() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitUntilExists(timeout: 10))
        for label in ["Home", "Closet", "Saved Looks"] {
            XCTAssertTrue(tabBar.buttons[label].exists, "Missing tab: \(label)")
        }
        XCTAssertTrue(tabBar.buttons["Home"].isSelected)
    }

    /// Each fixture set reaches the screens: Closet's header shows its piece count.
    @MainActor
    func testFixtureSetsReachTheScreens() {
        let expected = [
            ("demo", "17 pieces"),
            ("demo:offline", "17 pieces"),
            ("empty", "No pieces yet"),
        ]
        for (fixtures, text) in expected {
            let app = launchOnCloset(fixtures)
            let count = pieceCount(in: app)
            XCTAssertTrue(count.waitUntilExists(timeout: 10), "No piece count for \(fixtures)")
            XCTAssertTrue(count.label.hasSuffix(text), "\(fixtures): \(count.label)")
            app.terminate()
        }
    }

    /// The large closet loads, and a failing store shows Closet's error state with no count.
    @MainActor
    func testLargeAndFailingFixturesLaunch() {
        let large = launchOnCloset("large")
        let detail = pieceCount(in: large)
        XCTAssertTrue(detail.waitUntilExists(timeout: 10))
        // The number is formatted for the locale, for example "2,117".
        let count = Int(detail.label.filter(\.isNumber)) ?? 0
        XCTAssertGreaterThanOrEqual(count, 2_000, detail.label)
        large.terminate()

        let failing = launchOnCloset("demo:stores-fail")
        XCTAssertTrue(failing.staticTexts["Your closet didn’t load"].waitUntilExists(timeout: 10))
        XCTAssertTrue(failing.buttons["Try again"].exists)
        XCTAssertFalse(pieceCount(in: failing).label.contains("pieces"))
    }

    @MainActor
    private func launchOnCloset(_ fixtures: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", fixtures]
        app.launch()
        let closet = app.tabBars.firstMatch.buttons["Closet"]
        closet.tapUntilSelected(timeout: 10)
        return app
    }

    @MainActor
    private func pieceCount(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["closet.count"]
    }
}
