import XCTest

/// Profile essentials (Phase 14a): the name on the sign reaches Home (RD-03.1, RD-03.2), and a fit
/// value is refused when it's wrong and saved when it's right.
final class ProfileTests: XCTestCase {
    /// Waits end as soon as their condition holds, so this only matters on a slow machine.
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testChangingTheNameUpdatesTheSignOnHome() {
        let app = launch()
        XCTAssertTrue(app.buttons["Name sign: Lily"].waitUntilExists(timeout: Self.wait))

        openProfile(in: app)
        rename(to: "Rosa", in: app)
        // Profile's own sign shows it straight away.
        XCTAssertTrue(app.buttons["Name on your sign: Rosa"].waitUntilExists(timeout: Self.wait))
        app.goBack(from: "Profile", to: "Home", timeout: Self.wait)
        XCTAssertTrue(app.buttons["Name sign: Rosa"].waitUntilExists(timeout: Self.wait), "Home's sign didn't change")

        // An empty name: the sign says Hello, never a blank plate (RD-03.2).
        openProfile(in: app)
        rename(to: "", in: app)
        app.goBack(from: "Profile", to: "Home", timeout: Self.wait)
        XCTAssertTrue(app.buttons["Name sign, no name yet"].waitUntilExists(timeout: Self.wait))
    }

    @MainActor
    func testAFitValueIsRefusedWhenWrongAndSavedWhenRight() {
        let app = launch()
        openProfile(in: app)
        app.buttons["profile.fit"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Fit and measurements"].waitUntilExists(timeout: Self.wait))

        // The simulator is set to the US, so Waist is in inches.
        let waist = app.buttons["fit.waist"]
        waist.tapWhenHittable(timeout: Self.wait)
        let box = app.textFields["measurement.value"]
        XCTAssertTrue(box.waitUntilExists(timeout: Self.wait), "No measurement sheet")
        box.tapUntilFocused(timeout: Self.wait)
        box.typeText("270")
        app.buttons["measurement.save"].tap()
        let problem = app.descendants(matching: .any)["measurement.problem"]
        XCTAssertTrue(problem.waitUntilExists(timeout: Self.wait), "A waist of 270 inches was accepted")
        XCTAssertTrue(problem.label.contains("between 15 and 70"), problem.label)

        // Fix it: the problem goes as she types, and Save keeps it.
        box.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "27.5")
        XCTAssertTrue(problem.waitUntilGone(timeout: Self.wait))
        app.buttons["measurement.save"].tap()
        XCTAssertTrue(box.waitUntilGone(timeout: Self.wait), "The sheet didn't close after saving")
        XCTAssertEqual(waist.value as? String, "27.5 inches")

        // Height in feet and inches.
        let height = app.buttons["fit.height"]
        height.tapWhenHittable(timeout: Self.wait)
        let feet = app.textFields["measurement.feet"]
        XCTAssertTrue(feet.waitUntilExists(timeout: Self.wait))
        feet.tapUntilFocused(timeout: Self.wait)
        feet.typeText("4")
        let inches = app.textFields["measurement.inches"]
        inches.tapUntilFocused(timeout: Self.wait)
        inches.typeText("11")
        app.buttons["measurement.save"].tap()
        XCTAssertTrue(feet.waitUntilGone(timeout: Self.wait))
        XCTAssertEqual(height.value as? String, "4 feet 11 inches")

        // The usual fit is saved with one tap (LR-18).
        let fitted = app.buttons["fit.usual.fitted"]
        fitted.tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(fitted.waitUntilSelected(timeout: Self.wait))
        XCTAssertTrue(app.staticTexts["fit.usualNote"].exists)

        // Back on Profile and in again, the values are still there.
        app.goBack(from: "Fit and measurements", to: "Profile", timeout: Self.wait)
        app.buttons["profile.fit"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.buttons["fit.waist"].waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(app.buttons["fit.waist"].value as? String, "27.5 inches")
    }

    @MainActor
    func testTheTryOnPhotoSheetAddsAndRemovesTheExample() {
        let app = launch()
        openProfile(in: app)
        let row = app.buttons["profile.tryOnPhoto"]
        row.tapWhenHittable(timeout: Self.wait)
        app.buttons["tryOnPhoto.choose"].tapWhenHittable(timeout: Self.wait)
        app.buttons["tryOnPhoto.useExample"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.buttons["tryOnPhoto.remove"].waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(app.descendants(matching: .any)["tryOnPhoto.example"].exists)
        app.buttons["tryOnPhoto.remove"].tap()
        app.buttons["tryOnPhoto.confirmRemove"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.buttons["tryOnPhoto.choose"].waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(app.buttons["tryOnPhoto.remove"].exists)
        app.buttons["tryOnPhoto.done"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(row.label.contains("Not added"), row.label)
    }

    // MARK: Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: uiTestWait))
        return app
    }

    @MainActor
    private func openProfile(in app: XCUIApplication) {
        app.buttons["home.profile"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Profile"].waitUntilExists(timeout: Self.wait))
    }

    @MainActor
    private func rename(to name: String, in app: XCUIApplication) {
        app.buttons["profile.name"].tapWhenHittable(timeout: Self.wait)
        let field = app.descendants(matching: .any)["field.profile.nameField"]
        XCTAssertTrue(field.waitUntilExists(timeout: Self.wait), "No name field")
        // Tap near the end, so the cursor lands after the text before deleting it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        XCTAssertTrue(field.waitUntilFocused(timeout: Self.wait), "The name field didn't get the keyboard")
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + name)
        app.buttons["profile.nameSave"].tap()
        XCTAssertTrue(field.waitUntilGone(timeout: Self.wait), "The name sheet didn't close")
    }
}
