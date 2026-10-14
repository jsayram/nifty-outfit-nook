import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsTheTabBar() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixtures", "demo"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        for label in ["Home", "Closet", "Saved Looks"] {
            XCTAssertTrue(tabBar.buttons[label].exists, "Missing tab: \(label)")
        }
        XCTAssertTrue(tabBar.buttons["Home"].isSelected)
    }
}
