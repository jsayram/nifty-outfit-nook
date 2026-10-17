import XCTest

/// Remaining settings (Phase 14b): every Profile row opens something real, the Track laundry
/// switch reaches Home and Closet, Send feedback shows what goes before the share sheet, the desk
/// drawers open their screens, and Delete my data leaves a fresh app.
final class SettingsTests: XCTestCase {
    /// Waits end as soon as their condition holds, so this only matters on a slow machine.
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEveryProfileRowOpensSomethingReal() {
        let app = launch()
        openProfile(in: app)

        // Rows that push a screen: the screen's title, and one control only the real screen has.
        let pushed = [
            ("profile.fit", "Fit and measurements", "fit.waist"),
            ("profile.accessibility", "Accessibility", "accessibility.openSettings"),
            ("profile.help", "Help", "help.outfits"),
            ("profile.feedback", "Send feedback", "feedback.send"),
            ("profile.privacy", "Privacy and terms", "privacy.deleteData"),
            ("profile.deleteData", "Delete my data", "deleteData.delete"),
        ]
        for (row, title, control) in pushed {
            tap(row, in: app, opens: app.navigationBars[title])
            XCTAssertTrue(element(control, in: app).waitUntilExists(timeout: Self.wait), "\(title) has no \(control)")
            app.goBack(from: title, to: "Profile", timeout: Self.wait)
        }

        // Rows that open a sheet.
        let sheets = [
            ("profile.name", "field.profile.nameField"),
            ("profile.tryOnPhoto", "tryOnPhoto.choose"),
            ("profile.preferences", "profile.preferences.mineAndOneIdea"),
            ("profile.repeat", "profile.repeat.oneWeek"),
        ]
        for (row, control) in sheets {
            tap(row, in: app, opens: element(control, in: app))
            app.buttons["Close"].firstMatch.tapUntilGone(timeout: Self.wait)
        }

        // App tours waits for Phase 16b, when there are tours to replay.
        XCTAssertFalse(app.buttons["profile.tours"].exists)
    }

    /// RD-11: the switch turns tracking on and off; the hamper and Closet's Laundry tile follow,
    /// and turning it off keeps the dirty marks.
    @MainActor
    func testTrackLaundrySwitchReachesHomeAndCloset() {
        let app = launch()
        let hamper = app.buttons["home.hamper"]
        XCTAssertTrue(waitForLabel(of: hamper, containing: "Hamper: Laundry, Off"), hamper.label)

        openProfile(in: app)
        let laundry = app.switches["profile.laundry"]
        reveal(laundry, in: app)
        XCTAssertEqual(laundry.value as? String, "0")
        flip(laundry)
        XCTAssertTrue(waitForValue(of: laundry, "1"), "Track laundry didn't turn on")
        app.goBack(from: "Profile", to: "Home", timeout: Self.wait)
        // The demo's two kept marks come back (RD-11.2).
        XCTAssertTrue(waitForLabel(of: hamper, containing: "Hamper: Laundry, 2 to wash"), hamper.label)

        let tabs = app.tabBars.firstMatch
        tabs.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(element("closet.laundry", in: app).waitUntilExists(timeout: Self.wait), "No Laundry tile")

        // Off again from Closet's Profile button: the tile goes, the marks stay.
        app.buttons["closet.profile"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Profile"].waitUntilExists(timeout: Self.wait))
        reveal(laundry, in: app)
        flip(laundry)
        XCTAssertTrue(waitForValue(of: laundry, "0"), "Track laundry didn't turn off")
        XCTAssertTrue(waitForLabel(of: laundry, containing: "Your 2 dirty marks are kept."), laundry.label)
        app.goBack(from: "Profile", to: "Closet", timeout: Self.wait)
        XCTAssertTrue(element("closet.laundry", in: app).waitUntilGone(timeout: Self.wait))
        tabs.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: hamper, containing: "Hamper: Laundry, Off"), hamper.label)
    }

    /// The desk drawers (RD-10.1): Help, with Still stuck? leading to Send feedback; Send
    /// feedback shows exactly what goes and opens the share sheet; Privacy and terms leads to
    /// Delete my data.
    @MainActor
    func testDrawersAndSendFeedback() {
        let app = launch()

        tapDrawer("home.helpDrawer", in: app, opens: app.navigationBars["Help"])
        // The first topic is open; another opens on a tap.
        XCTAssertTrue(element("help.outfits.answer", in: app).waitUntilExists(timeout: Self.wait))
        tap("help.laundry", in: app, opens: element("help.laundry.answer", in: app))
        tap("help.stillStuck", in: app, opens: app.navigationBars["Send feedback"])

        // Send with nothing written: the problem shows, nothing opens.
        tap("feedback.send", in: app, opens: element("problem.feedback.message", in: app))

        let field =
            app.textViews["field.feedback.message"].exists
            ? app.textViews["field.feedback.message"] : app.textFields["field.feedback.message"]
        reveal(field, in: app)
        field.tapUntilFocused(timeout: Self.wait)
        field.typeText("The hamper is lovely")
        XCTAssertTrue(element("problem.feedback.message", in: app).waitUntilGone(timeout: Self.wait))
        let preview = element("feedback.previewText", in: app)
        XCTAssertTrue(waitForLabel(of: preview, containing: "The hamper is lovely"), preview.label)
        XCTAssertFalse(preview.label.contains("Device:"), "App details went in without asking")

        let details = app.switches["feedback.details"]
        reveal(details, in: app)
        flip(details)
        XCTAssertTrue(waitForLabel(of: preview, containing: "Device:"), preview.label)
        XCTAssertFalse(preview.label.contains("Lily"), "Her name went into the note")

        // Send opens the system share sheet; closing it keeps the note.
        let shareSheet = app.otherElements["ActivityListView"]
        tap("feedback.send", in: app, opens: shareSheet)
        // A tap while the sheet is still coming up can be lost, so tap Close until it goes.
        app.buttons["header.closeButton"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(shareSheet.waitUntilGone(timeout: Self.wait), "The share sheet didn't close")
        XCTAssertTrue(waitForLabel(of: preview, containing: "The hamper is lovely"))

        app.goBack(from: "Send feedback", to: "Help", timeout: Self.wait)
        app.goBack(from: "Help", to: "Home", timeout: Self.wait)

        // The note waits for her when she comes back from the drawer.
        tapDrawer("home.feedbackDrawer", in: app, opens: app.navigationBars["Send feedback"])
        XCTAssertTrue(waitForLabel(of: element("feedback.previewText", in: app), containing: "The hamper is lovely"))
        app.goBack(from: "Send feedback", to: "Home", timeout: Self.wait)

        tapDrawer("home.privacyDrawer", in: app, opens: app.navigationBars["Privacy and terms"])
        XCTAssertTrue(element("privacy.privacy", in: app).waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(element("privacy.terms", in: app).exists)
        tap("privacy.deleteData", in: app, opens: app.navigationBars["Delete my data"])
    }

    /// Delete my data: explained, asked once more, then everything goes and the app starts fresh
    /// on the welcome (Phase 17), then Home. Cancel deletes nothing.
    @MainActor
    func testDeleteMyDataResetsTheApp() {
        let app = launch()
        XCTAssertTrue(app.buttons["Name sign: Lily"].waitUntilExists(timeout: Self.wait))
        openProfile(in: app)
        tap("profile.deleteData", in: app, opens: app.navigationBars["Delete my data"])
        XCTAssertTrue(labelled("21 pieces", in: app).waitUntilExists(timeout: Self.wait), "No counts")

        // Cancel first: nothing changes. On CI the first tap on Delete was once lost (October
        // 2026), so each tap waits for the question and taps again if it didn't come.
        let alert = app.alerts["Delete everything?"]
        tap("deleteData.delete", in: app, opens: alert)
        alert.buttons["Cancel"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(alert.waitUntilGone(timeout: Self.wait))
        XCTAssertTrue(app.navigationBars["Delete my data"].exists)

        tap("deleteData.delete", in: app, opens: alert)
        alert.buttons["Delete everything"].tapUntilGone(timeout: Self.wait)

        // A fresh app: the welcome, with a note that it's done (Phase 17). Onboarding again, this
        // time with no name and the empty closet.
        XCTAssertTrue(
            app.buttons["welcome.getStarted"].waitUntilExists(timeout: Self.wait), "Didn't go back to the welcome")
        XCTAssertTrue(
            labelled("Your data is deleted", in: app).waitUntilExists(timeout: Self.wait), "No note that it's done")
        // Each step's button moves on to the next step; a lost tap is tapped once more.
        app.buttons["welcome.getStarted"].tapUntil(app.navigationBars["Your name"], appears: Self.wait)
        app.buttons["onboarding.skip"].tapUntil(app.navigationBars["Your closet stays here"], appears: Self.wait)
        app.buttons["onboarding.continue"].tapUntil(
            app.navigationBars["How you like clothes to fit"], appears: Self.wait)
        app.buttons["onboarding.skip"].tapUntil(app.navigationBars["Choose a starting closet"], appears: Self.wait)
        element("onboarding.closet.empty", in: app).tapUntilSelected(timeout: Self.wait)
        app.buttons["onboarding.continue"].tapUntil(app.navigationBars["Home"], appears: Self.wait)

        // Home: a sign with no name and an empty source.
        XCTAssertTrue(app.buttons["Name sign, no name yet"].waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(app.buttons["Suitcase: Source, Main closet, Empty, Whole closet"].exists)
        XCTAssertTrue(app.tabBars.firstMatch.buttons["Home"].isSelected)

        // Delete my data forgets the tours seen and turns tips back on, so Home's tour starts as
        // on a fresh install (Phase 16a), once onboarding hands over (Phase 17).
        let skip = app.buttons["tour.skip"]
        XCTAssertTrue(skip.waitUntilExists(timeout: Self.wait), "Home's tour didn't start after a fresh start")
        skip.tapUntilGone(timeout: Self.wait)

        // Closet is empty, and Saved Looks has nothing.
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(
            element("closet.empty.addPiece", in: app).waitUntilExists(timeout: Self.wait), "Closet isn't empty")
    }

    // MARK: Helpers

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: Self.wait))
        return app
    }

    @MainActor
    private func openProfile(in app: XCUIApplication) {
        app.buttons["home.profile"].tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Profile"].waitUntilExists(timeout: Self.wait))
    }

    /// Taps a desk drawer on Home and waits for what it opens.
    @MainActor
    private func tapDrawer(
        _ identifier: String, in app: XCUIApplication, opens next: XCUIElement, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let drawer = app.buttons[identifier]
        reveal(drawer, in: app, file: file, line: line)
        drawer.tapUntil(next, appears: Self.wait, file: file, line: line)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func labelled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// Taps an element by identifier, scrolling to it first, and waits for what it opens.
    @MainActor
    private func tap(
        _ identifier: String, in app: XCUIApplication, opens next: XCUIElement, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = element(identifier, in: app)
        reveal(target, in: app, file: file, line: line)
        target.tapUntil(next, appears: Self.wait, file: file, line: line)
    }

    /// Scrolls until the element can be tapped (see `XCUIApplication.reveal`).
    @MainActor
    private func reveal(
        _ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        app.reveal(element, timeout: Self.wait, file: file, line: line)
    }

    /// A SwiftUI switch's label doesn't flip it; the switch at its trailing end does. Waits until
    /// its value changes, tapping once more if the first tap was lost.
    @MainActor
    private func flip(_ toggle: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let before = toggle.value as? String
        let flipped: @MainActor () -> Bool = { (toggle.value as? String) != before }
        for _ in 0..<2 {
            let inner = toggle.switches.firstMatch
            if inner.exists {
                inner.tap()
            } else {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            if waitUntilTrue(timeout: Self.wait, flipped) { return }
        }
        XCTFail("\(toggle) didn't flip", file: file, line: line)
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return element.waitUntil(predicate, timeout: Self.wait)
    }

    @MainActor
    private func waitForValue(of element: XCUIElement, _ value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return element.waitUntil(predicate, timeout: Self.wait)
    }
}
