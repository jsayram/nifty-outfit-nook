import XCTest

/// Onboarding (Phase 17), the checkpoint "delete, reinstall, and go from first launch to the first
/// look": a fresh install (`-onboarding reset -tour reset`) opens on the welcome, the four steps
/// lead into Home with its tour, the laptop opens Style Me, and Style me shows the first look.
/// Then a relaunch opens Home straight away, and the tours she has seen don't come back.
///
/// These tests leave out `UITestLaunch.skipOnboarding` on purpose, and they leave the simulator's
/// app state as "onboarding done" with tours seen. Every other test sets its own with flags.
final class OnboardingTests: XCTestCase {
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFromFirstLaunchToTheFirstLookThenARelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding", "reset", "-tour", "reset", "-fixtures", "demo"]
        app.launch()

        // The welcome: the title, then Get started.
        XCTAssertTrue(app.staticTexts["welcome.title"].waitForExistence(timeout: Self.wait), "No welcome")
        XCTAssertTrue(app.buttons["welcome.alreadyUsing"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The tabs show behind onboarding")
        app.buttons["welcome.getStarted"].tapWhenHittable(timeout: Self.wait)

        // Step 1: her name, which the sign on the wall shows as she types.
        XCTAssertTrue(app.navigationBars["Your name"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(label("Step 1 of 4", in: app).exists)
        let field = app.textFields["field.onboarding.name"]
        field.tapWhenHittable(timeout: Self.wait)
        field.typeText("Lily")
        app.buttons["onboarding.continue"].tapWhenHittable(timeout: Self.wait)

        // Step 2: where her things stay. Nothing to choose.
        XCTAssertTrue(app.navigationBars["Your closet stays here"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(element("onboarding.forgets", in: app).exists, "No word that the test build forgets")
        XCTAssertFalse(app.buttons["onboarding.skip"].exists, "The privacy step can be skipped")
        app.buttons["onboarding.continue"].tapWhenHittable(timeout: Self.wait)

        // Step 3: her usual fit.
        XCTAssertTrue(app.navigationBars["How you like clothes to fit"].waitForExistence(timeout: Self.wait))
        let comfortable = app.buttons["onboarding.fit.comfortable"]
        comfortable.tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(comfortable.isSelected)
        app.buttons["onboarding.continue"].tapWhenHittable(timeout: Self.wait)

        // Step 4: the sample closet is chosen to start; Go to my room.
        XCTAssertTrue(app.navigationBars["Choose a starting closet"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(element("onboarding.closet.sample", in: app).isSelected)
        let finish = app.buttons["onboarding.continue"]
        XCTAssertEqual(finish.label, "Go to my room")
        finish.tapWhenHittable(timeout: Self.wait)

        // Home, with its tour straight away (PRD §7.8). Through to Start styling.
        let card = app.descendants(matching: .any)["tour.card"]
        XCTAssertTrue(card.waitForExistence(timeout: Self.wait), "Home's tour didn't start after onboarding")
        let next = app.buttons["tour.next"]
        for _ in 0..<3 {
            next.tapWhenHittable(timeout: Self.wait)
        }
        XCTAssertTrue(waitForLabel(of: next, "Start styling"))
        next.tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(app.buttons["Name sign: Lily"].waitForExistence(timeout: Self.wait), "The sign lost her name")

        // The laptop opens Style Me, whose own tour shows the first time; Style me shows the look.
        app.buttons["home.laptop"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Style Me"].waitForExistence(timeout: Self.wait))
        skipTour(in: app)
        tapScrolling("styleMe.go", in: app)
        XCTAssertTrue(app.navigationBars["Your looks"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(
            app.buttons["results.version.simple"].waitForExistence(timeout: Self.wait), "No first look")
        skipTour(in: app)

        // Relaunch as Lily would: no flags but the sample data.
        app.terminate()
        app.launchArguments = ["-fixtures", "demo"]
        app.launch()

        // Home straight away, not the welcome, and Home's tour doesn't come back.
        XCTAssertTrue(app.buttons["home.laptop"].waitUntilHittable(timeout: Self.wait), "Didn't open on Home")
        XCTAssertFalse(app.buttons["welcome.getStarted"].exists, "Onboarding showed again")
        XCTAssertFalse(card.waitForExistence(timeout: 3), "Home's tour came back after a relaunch")
        // The test build forgets her name: the sample closet comes back as it started.
        XCTAssertTrue(app.buttons["Name sign, no name yet"].exists)

        // Style Me's tour was seen too.
        app.buttons["home.laptop"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Style Me"].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(card.waitForExistence(timeout: 3), "Style Me's tour came back after a relaunch")
    }

    /// "I already use Nifty Outfit Nook" goes straight to Home on the sample closet, with no name.
    @MainActor
    func testAlreadyUsingSkipsTheSetup() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding", "reset", "-tour", "off", "-fixtures", "demo"]
        app.launch()
        app.buttons["welcome.alreadyUsing"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.buttons["home.laptop"].waitUntilHittable(timeout: Self.wait), "Didn't open Home")
        XCTAssertTrue(app.buttons["Name sign, no name yet"].exists)
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(element("closet.count", in: app).waitForExistence(timeout: Self.wait))
        XCTAssertFalse(element("closet.empty.addPiece", in: app).exists, "The sample closet is empty")
    }

    // MARK: Helpers

    /// Skips the quick tour that's showing, once it has shown.
    @MainActor
    private func skipTour(in app: XCUIApplication) {
        let skip = app.buttons["tour.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: Self.wait), "No tour on a first visit")
        skip.tapUntilGone(timeout: Self.wait)
    }

    /// Taps a button by identifier, scrolling up to find it if it's below the screen.
    @MainActor
    private func tapScrolling(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: Self.wait), "No button \(identifier)")
        var swipes = 0
        while !button.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        button.tapWhenHittable(timeout: Self.wait)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func label(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, _ label: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: Self.wait) == .completed
    }
}
