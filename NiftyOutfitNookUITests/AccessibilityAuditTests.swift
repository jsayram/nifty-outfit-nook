import XCTest

/// Xcode's accessibility audit (`performAccessibilityAudit`) on every main screen, at the default
/// text size: one audit per screen on every pull request. `AccessibilityAuditLargeTextTests` runs
/// the same walk at the largest size (AX5), in the full suite only.
///
/// The audit is the closest thing to a VoiceOver pass a UI test can run: it checks contrast,
/// elements VoiceOver can't find, hit regions under 44 points, missing or poor labels, Dynamic
/// Type, clipped text and traits, on whatever is on screen when it runs. It can't move VoiceOver
/// or hear it, so `docs/accessibility-audit.md` lists what still needs a device.
///
/// An issue fails the test unless `AuditExclusions` names it with a reason.
class AccessibilityAuditTests: XCTestCase {
    static let wait = uiTestWait

    /// The text size these tests run at, or nil for the simulator's default.
    class var textSize: String? { nil }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: The walks

    /// The welcome and the four onboarding steps.
    @MainActor
    func testOnboarding() throws {
        let app = launch(["-onboarding", "reset", "-tour", "off", "-fixtures", "demo"] + UITestLaunch.animationsOff)
        XCTAssertTrue(app.buttons["welcome.getStarted"].waitUntilExists(timeout: Self.wait), "No welcome")
        try audit("Welcome", in: app)
        open("welcome.getStarted", showing: app.navigationBars["Your name"], in: app)
        try audit("Onboarding: your name", in: app)
        for title in ["Your closet stays here", "How you like clothes to fit", "Choose a starting closet"] {
            open("onboarding.continue", showing: app.navigationBars[title], in: app)
            try audit("Onboarding: \(title)", in: app)
        }
    }

    /// Home, then Home with its quick tour on the first step.
    @MainActor
    func testHomeAndItsTour() throws {
        let app = launch(UITestLaunch.standard + ["-fixtures", "demo"])
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: Self.wait))
        try audit("Home", in: app)
        app.terminate()

        let toured = launch(UITestLaunch.skipOnboarding + ["-tour", "off,home", "-fixtures", "demo"])
        XCTAssertTrue(element("tour.card", in: toured).waitUntilExists(timeout: Self.wait), "No tour")
        try audit("Home's tour", in: toured)
    }

    /// Closet, a piece, Suitcases, a suitcase, Laundry, and Add a piece and its form.
    @MainActor
    func testClosetAndItsScreens() throws {
        let app = launch(UITestLaunch.standard + ["-fixtures", "demo:laundry=some"])
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(element("closet.count", in: app).waitUntilExists(timeout: Self.wait))
        try audit("Closet", in: app)

        open("closet.garment.g-navy-trousers", showing: element("garment.name", in: app), in: app)
        try audit("A piece", in: app)
        app.goBack(from: app.navigationBars.element(boundBy: 0).identifier, to: "Closet", timeout: Self.wait)

        open("closet.suitcases", showing: app.navigationBars["Suitcases"], in: app)
        try audit("Suitcases", in: app)
        open("suitcases.row.s-weekend.open", showing: element("suitcase.count", in: app), in: app)
        try audit("A suitcase", in: app)
        app.navigationBars.firstMatch.buttons.firstMatch.tapUntil(app.navigationBars["Suitcases"], appears: Self.wait)
        app.goBack(from: "Suitcases", to: "Closet", timeout: Self.wait)

        open("closet.laundry", showing: app.navigationBars["Laundry"], in: app)
        try audit("Laundry", in: app)
        app.goBack(from: "Laundry", to: "Closet", timeout: Self.wait)

        open("closet.addPiece", showing: app.buttons["addPiece.words"], in: app)
        try audit("Add a piece", in: app)
        open("addPiece.words", showing: app.buttons["words.continue"], in: app)
        open("words.continue", showing: element("field.name", in: app), in: app)
        try audit("Add a piece: the form", in: app)
    }

    /// Style Me, Your looks (Today and Saved) and Swap a piece.
    @MainActor
    func testStyleMeAndYourLooks() throws {
        let app = launch(UITestLaunch.standard + ["-fixtures", "demo"])
        open("home.laptop", showing: app.navigationBars["Style Me"], in: app)
        try audit("Style Me", in: app)
        open("styleMe.go", showing: app.buttons["results.version.simple"], in: app)
        try audit("Your looks", in: app)
        open("results.swap", showing: app.navigationBars["Swap a piece"], in: app)
        try audit("Swap a piece", in: app)
        app.goBack(from: "Swap a piece", to: "Your looks", timeout: Self.wait)
        let saved = app.buttons["results.tab.saved"]
        reveal(saved, in: app)
        saved.tapUntilSelected(timeout: Self.wait)
        try audit("Your looks: Saved", in: app)
    }

    /// Saved Looks, a look, the Pictures tab and a picture.
    @MainActor
    func testSavedLooksAndPictures() throws {
        let app = launch(UITestLaunch.standard + ["-fixtures", "demo"])
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(app.searchFields.firstMatch.waitUntilExists(timeout: Self.wait))
        try audit("Saved Looks", in: app)
        open("savedLooks.look.o-lace-date", showing: element("lookDetail.name", in: app), in: app)
        try audit("A saved look", in: app)
        app.goBack(from: app.navigationBars.element(boundBy: 0).identifier, to: "Saved Looks", timeout: Self.wait)

        let pictures = app.buttons["savedLooks.tab.pictures"]
        reveal(pictures, in: app)
        pictures.tapUntilSelected(timeout: Self.wait)
        try audit("Pictures", in: app)
        open("savedLooks.picture.p-lace", showing: element("picture.title", in: app), in: app)
        try audit("A picture", in: app)
    }

    /// Profile, Fit and measurements, and the settings screens. Each row opens the real screen:
    /// its title, and one control only that screen has (this also stands in for a separate
    /// "every Profile row opens something" test that walked the same rows).
    @MainActor
    func testProfileAndSettings() throws {
        let app = launch(UITestLaunch.standard + ["-fixtures", "demo"])
        open("home.profile", showing: app.navigationBars["Profile"], in: app)
        try audit("Profile", in: app)
        let pushed = [
            ("profile.fit", "Fit and measurements", "fit.waist"),
            ("profile.accessibility", "Accessibility", "accessibility.openSettings"),
            ("profile.help", "Help", "help.outfits"),
            ("profile.feedback", "Send feedback", "feedback.send"),
            ("profile.privacy", "Privacy and terms", "privacy.deleteData"),
            ("profile.deleteData", "Delete my data", "deleteData.delete"),
        ]
        for (row, title, control) in pushed {
            open(row, showing: app.navigationBars[title], in: app)
            XCTAssertTrue(element(control, in: app).waitUntilExists(timeout: Self.wait), "\(title) has no \(control)")
            try audit(title, in: app)
            app.goBack(from: title, to: "Profile", timeout: Self.wait)
        }
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            arguments + (Self.textSize.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        app.launch()
        return app
    }

    /// Runs the audit on what's on screen. Each issue fails the test unless `AuditExclusions`
    /// excuses it.
    @MainActor
    private func audit(_ screen: String, in app: XCUIApplication) throws {
        // The room art and look bundles are drawn a moment after the screen appears.
        waitUntilStill()
        let exclusions = AuditExclusions(screen: screen, in: app)
        var failures: [String] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            if exclusions.reason(for: issue) == nil {
                failures.append(exclusions.describe(issue))
            } else if issue.auditType == .textClipped, issue.element == nil {
                // Evidence for the exclusion: what the screen looked like when the audit said
                // its text was clipped.
                let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                evidence.name = "Excused clipped text: \(screen)"
                evidence.lifetime = .keepAlways
                self.add(evidence)
            }
            // Handled here either way: the failures are reported below with what they're about,
            // which the audit's own message ("Contrast failed") leaves out.
            return true
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    /// Waits until two screenshots a quarter of a second apart are the same, for up to five
    /// seconds: the drawings are in and nothing is moving.
    @MainActor
    private func waitUntilStill() {
        var last = Data()
        _ = waitUntilTrue(timeout: 5) {
            let now = XCUIScreen.main.screenshot().pngRepresentation
            defer { last = now }
            return now == last
        }
    }

    /// Taps a button that moves the app on, scrolling to it first, and waits for `next`.
    @MainActor
    private func open(
        _ identifier: String, showing next: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = app.buttons[identifier]
        reveal(button, in: app, file: file, line: line)
        button.tapUntil(next, appears: Self.wait, file: file, line: line)
    }

    @MainActor
    private func reveal(
        _ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        // A lazy grid makes a piece only once it's near the screen, so at large sizes scroll
        // down until it exists.
        if !element.waitUntilExists(timeout: 1) {
            for _ in 0..<10 where !element.exists {
                app.dragPage(up: true)
            }
        }
        XCTAssertTrue(element.waitUntilExists(timeout: Self.wait), "Missing \(element)", file: file, line: line)
        app.scrollUntilHittable(element, up: 10, down: 10)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

/// The same walk at the largest text size, AX5. It audits the screens the default-size walk
/// already audits on every pull request, so it runs in the full suite only.
final class AccessibilityAuditLargeTextTests: AccessibilityAuditTests {
    override class var textSize: String? { "UICTContentSizeCategoryAccessibilityXXXL" }

    override func setUpWithError() throws {
        try skipOnPullRequests("The default-size walk audits the same screens on every pull request.")
        try super.setUpWithError()
    }
}
