import XCTest

/// The debug Device checks screen (`-device-checks`): it opens, reads the app's own folders and
/// says what the store and its last launch did. On a simulator the file classes mean nothing (it
/// keeps none), so this only checks that every section is there. The classes are for a real phone.
final class DeviceChecksTests: XCTestCase {
    private static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTheScreenShowsEverySection() {
        let app = XCUIApplication()
        app.launchArguments = ["-device-checks"] + UITestLaunch.animationsOff
        app.launch()
        XCTAssertTrue(app.navigationBars["Device checks"].waitUntilExists(timeout: Self.wait))

        let overall = app.staticTexts["deviceChecks.overall"]
        XCTAssertTrue(overall.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(app.buttons["deviceChecks.copy"].exists)

        // The store opened at launch, so its lines are there once the screen has read them.
        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Store version on disk'"))
            .firstMatch
        // The list builds its rows as they scroll into view.
        app.scrollUntilHittable(version, up: 8)
        XCTAssertTrue(version.exists, "No store line on the screen")
        // Read live, from the store the app has open.
        let integrity = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Integrity check: ok'"))
            .firstMatch
        app.scrollUntilHittable(integrity, up: 8)
        XCTAssertTrue(integrity.exists, "The store's integrity check didn't say ok")
        let lock = app.staticTexts["Locked-phone test"]
        app.scrollUntilHittable(lock, up: 8)
        XCTAssertTrue(lock.exists, "No locked-phone section on the screen")
    }
}
