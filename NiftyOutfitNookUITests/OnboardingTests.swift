import XCTest

/// Onboarding (Phase 17), the checkpoint "delete, reinstall, and go from first launch to the first
/// look": a fresh install (`-onboarding reset -tour reset`) opens on the welcome, the four steps
/// lead into Home with its tour, the laptop opens Style Me, and Style me shows the first look.
/// Then a relaunch opens Home straight away, and the tours she has seen don't come back.
///
/// These tests leave out `UITestLaunch.skipOnboarding` on purpose, and they leave the simulator's
/// app state as "onboarding done" with tours seen. Every other test sets its own with flags.
final class OnboardingTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFromFirstLaunchToTheFirstLookThenARelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding", "reset", "-tour", "reset", "-fixtures", "demo"]
        app.launch()

        // The welcome: the title, then Get started.
        XCTAssertTrue(app.staticTexts["welcome.title"].waitUntilExists(timeout: Self.wait), "No welcome")
        XCTAssertTrue(app.buttons["welcome.alreadyUsing"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The tabs show behind onboarding")
        // Each step's button moves on to the next step; on CI a lost tap is tapped once more.
        app.buttons["welcome.getStarted"].tapUntil(app.navigationBars["Your name"], appears: Self.wait)

        // Step 1: her name, which the sign on the wall shows as she types.
        XCTAssertTrue(app.buttons["welcome.getStarted"].waitUntilGone(timeout: Self.wait))
        XCTAssertTrue(label("Step 1 of 4", in: app).exists)
        let field = app.textFields["field.onboarding.name"]
        field.tapUntilFocused(timeout: Self.wait)
        field.typeText("Lily")
        app.buttons["onboarding.continue"].tapUntil(app.navigationBars["Your closet stays here"], appears: Self.wait)

        // Step 2: where her things stay. Nothing to choose.
        waitForStep("Your closet stays here", after: "Your name", in: app)
        XCTAssertTrue(element("onboarding.forgets", in: app).exists, "No word that the test build forgets")
        XCTAssertFalse(app.buttons["onboarding.skip"].exists, "The privacy step can be skipped")
        app.buttons["onboarding.continue"].tapUntil(
            app.navigationBars["How you like clothes to fit"], appears: Self.wait)

        // Step 3: her usual fit.
        waitForStep("How you like clothes to fit", after: "Your closet stays here", in: app)
        let comfortable = app.buttons["onboarding.fit.comfortable"]
        comfortable.tapUntilSelected(timeout: Self.wait)
        app.buttons["onboarding.continue"].tapUntil(app.navigationBars["Choose a starting closet"], appears: Self.wait)

        // Step 4: the sample closet is chosen to start; Go to my room.
        waitForStep("Choose a starting closet", after: "How you like clothes to fit", in: app)
        XCTAssertTrue(element("onboarding.closet.sample", in: app).isSelected)
        let finish = app.buttons["onboarding.continue"]
        XCTAssertEqual(finish.label, "Go to my room")
        finish.tapWhenHittable(timeout: Self.wait)

        // Home, with its tour straight away (PRD §7.8). Through to Start styling.
        let card = app.descendants(matching: .any)["tour.card"]
        XCTAssertTrue(card.waitUntilExists(timeout: Self.wait), "Home's tour didn't start after onboarding")
        let next = app.buttons["tour.next"]
        for _ in 0..<3 {
            next.tapWhenHittable(timeout: Self.wait)
        }
        XCTAssertTrue(waitForLabel(of: next, "Start styling"))
        next.tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(app.buttons["Name sign: Lily"].waitUntilExists(timeout: Self.wait), "The sign lost her name")

        // The laptop opens Style Me, whose own tour shows the first time; Style me shows the look.
        app.buttons["home.laptop"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Style Me"].waitUntilExists(timeout: Self.wait))
        skipTour(in: app)
        tapScrolling("styleMe.go", in: app)
        XCTAssertTrue(app.navigationBars["Your looks"].waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(
            app.buttons["results.version.simple"].waitUntilExists(timeout: Self.wait), "No first look")
        skipTour(in: app)

        // Relaunch as Lily would: no flags but the sample data.
        app.terminate()
        app.launchArguments = ["-fixtures", "demo"]
        app.launch()

        // Home straight away, not the welcome, and Home's tour doesn't come back.
        XCTAssertTrue(app.buttons["home.laptop"].waitUntilHittable(timeout: Self.wait), "Didn't open on Home")
        XCTAssertFalse(app.buttons["welcome.getStarted"].exists, "Onboarding showed again")
        XCTAssertFalse(card.waitUntilExists(timeout: 3), "Home's tour came back after a relaunch")
        // The test build forgets her name: the sample closet comes back as it started.
        XCTAssertTrue(app.buttons["Name sign, no name yet"].exists)

        // Style Me's tour was seen too.
        app.buttons["home.laptop"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Style Me"].waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(card.waitUntilExists(timeout: 3), "Style Me's tour came back after a relaunch")
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
        XCTAssertTrue(element("closet.count", in: app).waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(element("closet.empty.addPiece", in: app).exists, "The sample closet is empty")
    }

    // MARK: Helpers

    /// Skips the quick tour that's showing, once it has shown.
    /// Waits for the onboarding step titled `title`, and for the step before it to have slid
    /// away. While a step slides in, both steps' Continue buttons exist, and on CI a query then
    /// matched two of them ("Multiple matching elements found").
    @MainActor
    private func waitForStep(
        _ title: String, after previous: String, in app: XCUIApplication, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.navigationBars[title].waitUntilExists(timeout: Self.wait), "No \(title)", file: file, line: line)
        XCTAssertTrue(
            app.navigationBars[previous].waitUntilGone(timeout: Self.wait), "\(previous) didn't go", file: file,
            line: line)
    }

    @MainActor
    private func skipTour(in app: XCUIApplication) {
        let skip = app.buttons["tour.skip"]
        XCTAssertTrue(skip.waitUntilExists(timeout: Self.wait), "No tour on a first visit")
        skip.tapUntilGone(timeout: Self.wait)
    }

    /// Taps a button by identifier, scrolling up to find it if it's below the screen.
    @MainActor
    private func tapScrolling(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(identifier)")
        app.scrollUntilHittable(button, up: 12)
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
        return element.waitUntil(NSPredicate(format: "label == %@", label), timeout: Self.wait)
    }
}
