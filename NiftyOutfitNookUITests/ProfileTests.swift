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

    /// Merges and nightly only (79 seconds). What is refused and why, the units she typed in, feet
    /// and inches, clearing, and that the store keeps the values are `ProfileModelTests` and
    /// `MeasurementEntryTests`. Typing into a sheet and saving it is still checked on every pull
    /// request by `testChangingTheNameUpdatesTheSignOnHome`, and the Fit screen opens in
    /// `AccessibilityAuditTests.testProfileAndSettings`.
    @MainActor
    func testAFitValueIsRefusedWhenWrongAndSavedWhenRight() throws {
        try skipOnPullRequests("ProfileModelTests and MeasurementEntryTests cover the rules and the saving.")
        let app = launch()
        openProfile(in: app)
        app.buttons["profile.fit"].tapUntil(app.navigationBars["Fit and measurements"], appears: Self.wait)

        // The simulator is set to the US, so Waist is in inches.
        let waist = app.buttons["fit.waist"]
        let box = app.textFields["measurement.value"]
        waist.tapUntil(box, appears: Self.wait)
        box.tapUntilFocused(timeout: Self.wait)
        box.typeTextAndWait("270", timeout: Self.wait)
        let problem = app.descendants(matching: .any)["measurement.problem"]
        app.buttons["measurement.save"].tapUntil(problem, appears: Self.wait)
        XCTAssertTrue(problem.label.contains("between 15 and 70"), problem.label)

        // Fix it: the problem goes as she types, and Save keeps it.
        box.typeTextAndWait(
            String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "27.5", expecting: "27.5", timeout: Self.wait
        )
        XCTAssertTrue(problem.waitUntilGone(timeout: Self.wait))
        app.buttons["measurement.save"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(box.waitUntilGone(timeout: Self.wait), "The sheet didn't close after saving")
        XCTAssertEqual(waist.value as? String, "27.5 inches")

        // Height in feet and inches.
        let height = app.buttons["fit.height"]
        let feet = app.textFields["measurement.feet"]
        height.tapUntil(feet, appears: Self.wait)
        feet.tapUntilFocused(timeout: Self.wait)
        feet.typeTextAndWait("4", timeout: Self.wait)
        let inches = app.textFields["measurement.inches"]
        inches.tapUntilFocused(timeout: Self.wait)
        inches.typeTextAndWait("11", timeout: Self.wait)
        app.buttons["measurement.save"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(feet.waitUntilGone(timeout: Self.wait))
        XCTAssertEqual(height.value as? String, "4 feet 11 inches")

        // The usual fit is saved with one tap (LR-18).
        let fitted = app.buttons["fit.usual.fitted"]
        fitted.tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(app.staticTexts["fit.usualNote"].exists)

        // Back on Profile and in again, the values are still there.
        app.goBack(from: "Fit and measurements", to: "Profile", timeout: Self.wait)
        app.buttons["profile.fit"].tapUntil(app.navigationBars["Fit and measurements"], appears: Self.wait)
        XCTAssertTrue(app.buttons["fit.waist"].waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(app.buttons["fit.waist"].value as? String, "27.5 inches")
    }

    @MainActor
    func testTheTryOnPhotoSheetAddsAndRemovesTheExample() {
        let app = launch()
        openProfile(in: app)
        let row = app.buttons["profile.tryOnPhoto"]
        row.tapUntil(app.buttons["tryOnPhoto.choose"], appears: Self.wait)
        app.buttons["tryOnPhoto.choose"].tapUntil(app.buttons["tryOnPhoto.useExample"], appears: Self.wait)
        app.buttons["tryOnPhoto.useExample"].tapUntil(app.buttons["tryOnPhoto.remove"], appears: Self.wait)
        XCTAssertTrue(app.descendants(matching: .any)["tryOnPhoto.example"].exists)
        app.buttons["tryOnPhoto.remove"].tapUntil(app.buttons["tryOnPhoto.confirmRemove"], appears: Self.wait)
        app.buttons["tryOnPhoto.confirmRemove"].tapUntilGone(timeout: Self.wait)
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
        app.buttons["home.profile"].tapUntil(app.navigationBars["Profile"], appears: Self.wait)
    }

    @MainActor
    private func rename(to name: String, in app: XCUIApplication) {
        let field = app.descendants(matching: .any)["field.profile.nameField"]
        app.buttons["profile.name"].tapUntil(field, appears: Self.wait)
        // Tap near the end, so the cursor lands after the text before deleting it.
        let focused = field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tapUntil(timeout: Self.wait) {
            field.hasKeyboardNow
        }
        XCTAssertTrue(focused, "The name field didn't get the keyboard")
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + name)
        // An empty field shows its prompt as its value, so check the old name went instead.
        let typed = waitUntilTrue(timeout: Self.wait) {
            let value = (field.value as? String) ?? ""
            return name.isEmpty ? !value.contains(current) : value == name
        }
        XCTAssertTrue(typed, "The name field shows \(String(describing: field.value)), not \"\(name)\"")
        app.buttons["profile.nameSave"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(field.waitUntilGone(timeout: Self.wait), "The name sheet didn't close")
    }
}
