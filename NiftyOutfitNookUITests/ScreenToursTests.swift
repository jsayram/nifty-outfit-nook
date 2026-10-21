import XCTest

/// The other screens' quick tours (Phase 16b, PRD §7.8, AC-103): on a fresh install each screen
/// shows its tour once, App tours on Profile replays any of them from step 1, and with "Show tips
/// on new screens" off nothing starts by itself.
///
/// Two long walks rather than one test per screen, to keep CI time down. The Stage A audit's six
/// tours (Recently deleted, All suitcases, Delete my data, Accessibility, Try it on and editing
/// a piece) are on the same walks. The card's words, its
/// buttons and the overlay being modal are covered by `HomeTourTests`; these check which tour
/// shows where, and when.
///
/// Merges to develop and main and nightly only (October 2026). Together the two walks took 257
/// seconds, the slowest tests in the suite after the accessibility audits. Which tour a screen
/// has, how many steps, when it starts, tips off, replay, Reset all tips and one tour at a time
/// are all package tests (`ScreenToursTests` and `TourCenterTests` in FeaturesTests,
/// `TourTests`, `TourStoreTests`), the cards are snapshot tests (`ScreenTourSnapshotTests`), and
/// `HomeTourTests` keeps the real overlay under test on every pull request. What these two walks
/// add is that each screen really attaches its tour, which the merge run still checks.
final class ScreenToursTests: XCTestCase {
    static let wait = uiTestWait

    override func setUpWithError() throws {
        try skipOnPullRequests("The tours' rules are package tests and Home's tour is in HomeTourTests.")
        continueAfterFailure = false
    }

    /// `-tour reset`, as on a fresh install: each screen's tour shows the first time it opens,
    /// once, and never over another one.
    @MainActor
    func testFreshInstallShowsEachTourOnce() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.skipOnboarding + ["-tour", "reset", "-fixtures", "demo:laundry=some"]
        app.launch()
        expectTour("Style Me", step: 1, of: 4, in: app)
        skip(in: app)

        // Closet, walked to the end.
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        expectTour("Add your clothes", step: 1, of: 3, in: app)
        next(to: "Find a piece", step: 2, of: 3, in: app)
        next(to: "Narrow it down", step: 3, of: 3, in: app)
        XCTAssertEqual(app.buttons["tour.next"].label, "Got it")
        app.buttons["tour.next"].tapUntilGone(timeout: Self.wait)

        // A piece, then back to Closet: its tour doesn't come back.
        let piece = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'closet.garment.'")).firstMatch
        piece.tapUntil(app.buttons["garment.edit"], appears: Self.wait)
        expectTour("Change the details", step: 1, of: 3, in: app)
        skip(in: app)
        // Editing it has its own tour (Stage A audit). Cancel with nothing changed just closes.
        tap("garment.edit", in: app, showing: app.buttons["editor.cancel"])
        expectTour("The picture", step: 1, of: 3, in: app)
        skip(in: app)
        app.buttons["editor.cancel"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(app.buttons["garment.edit"].waitUntilHittable(timeout: Self.wait))
        let edit = app.buttons["garment.edit"]
        app.navigationBars.buttons.element(boundBy: 0).tapUntil(timeout: Self.wait, else: "The piece didn't close") {
            !edit.exists
        }
        XCTAssertTrue(app.buttons["closet.addPiece"].waitUntilHittable(timeout: Self.wait))
        expectNoTour(in: app)

        // Recently deleted (Stage A audit).
        tap("closet.recentlyDeleted", in: app, showing: app.navigationBars["Recently deleted"])
        expectTour("Kept for 30 days", step: 1, of: 2, in: app)
        skip(in: app)
        app.goBack(from: "Recently deleted", to: "Closet", timeout: Self.wait)

        // Suitcases and Laundry, on the Closet tab.
        tap("closet.suitcases", in: app, showing: app.navigationBars["Suitcases"])
        expectTour("Pack a little collection", step: 1, of: 2, in: app)
        skip(in: app)
        // See all (Stage A audit). The demo has an archived suitcase, so three tips.
        tap("suitcases.seeAll", in: app, showing: app.navigationBars["All suitcases"])
        expectTour("Find a suitcase", step: 1, of: 3, in: app)
        skip(in: app)
        app.goBack(from: "All suitcases", to: "Suitcases", timeout: Self.wait)
        app.goBack(from: "Suitcases", to: "Closet", timeout: Self.wait)
        tap("closet.laundry", in: app, showing: app.navigationBars["Laundry"])
        expectTour("Fresh from the wash?", step: 1, of: 2, in: app)
        skip(in: app)
        app.goBack(from: "Laundry", to: "Closet", timeout: Self.wait)

        // Saved Looks, a look, and Swap a piece from it.
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        expectTour("Your favourite outfits", step: 1, of: 3, in: app)
        skip(in: app)
        let look = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'savedLooks.look.'")).firstMatch
        look.tapUntil(app.buttons["lookDetail.swap"], appears: Self.wait)
        expectTour("Wear this one", step: 1, of: 3, in: app)
        skip(in: app)
        tap("lookDetail.swap", in: app, showing: app.navigationBars["Swap a piece"])
        expectTour("Which piece?", step: 1, of: 4, in: app)
        skip(in: app)

        // Style Me from the laptop, then Your looks once the looks are ready.
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        expectNoTour(in: app)
        app.buttons["home.laptop"].tapUntil(app.navigationBars["Style Me"], appears: Self.wait)
        expectTour("Which clothes?", step: 1, of: 3, in: app)
        skip(in: app)
        tap("styleMe.go", in: app, showing: app.navigationBars["Your looks"])
        expectTour("Three versions", step: 1, of: 4, in: app)
        skip(in: app)

        // Try it on is a sheet, which draws its own tour over itself (Stage A audit).
        tap("results.tryOn", in: app, showing: app.buttons["tryOn.make"])
        expectTour("A simulated picture", step: 1, of: 2, in: app)
        next(to: "Only when you ask", step: 2, of: 2, in: app)
        app.buttons["tour.next"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(app.buttons["tryOn.make"].waitUntilHittable(timeout: Self.wait), "The sheet is still covered")
        app.buttons["Close"].firstMatch.tapUntilGone(timeout: Self.wait)
        app.goBack(from: "Your looks", to: "Style Me", timeout: Self.wait)
        expectNoTour(in: app)

        // Profile, then Accessibility and Delete my data under it (Stage A audit).
        app.goBack(from: "Style Me", to: "Home", timeout: Self.wait)
        app.buttons["home.profile"].tapUntil(app.navigationBars["Profile"], appears: Self.wait)
        expectTour("Your name on the sign", step: 1, of: 3, in: app)
        skip(in: app)
        tap("profile.accessibility", in: app, showing: app.navigationBars["Accessibility"])
        expectTour("It follows your iPhone", step: 1, of: 2, in: app)
        skip(in: app)
        app.goBack(from: "Accessibility", to: "Profile", timeout: Self.wait)
        tap("profile.deleteData", in: app, showing: app.navigationBars["Delete my data"])
        expectTour("What goes", step: 1, of: 2, in: app)
        skip(in: app)
        app.goBack(from: "Delete my data", to: "Profile", timeout: Self.wait)
        expectNoTour(in: app)
    }

    /// With tips off nothing starts by itself. App tours replays a tour on its screen from
    /// step 1, turning tips on lets a new screen's tour start, and Reset all tips brings back
    /// one that was seen.
    @MainActor
    func testReplayFromProfileAndTipsOff() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo"]
        app.launch()

        // Tips off: no tour on Closet or Profile.
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(app.buttons["closet.addPiece"].waitUntilHittable(timeout: Self.wait))
        expectNoTour(in: app)
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        app.buttons["home.profile"].tapUntil(app.navigationBars["Profile"], appears: Self.wait)
        expectNoTour(in: app)

        // App tours lists the screens, with the switch off.
        openAppTours(in: app)
        let tips = app.switches["appTours.showTips"]
        XCTAssertTrue(tips.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(waitForValue("0", of: tips), "Tips should be off")
        XCTAssertTrue(app.buttons["appTours.closet"].exists)
        XCTAssertFalse(app.buttons["appTours.help"].isHittable, "Help should be under More screen tours")

        // Replay Closet: the sheet closes, Closet opens, and its tour starts at step 1.
        let closetTab = app.tabBars.firstMatch.buttons["Closet"]
        app.buttons["appTours.closet"].tapUntil(timeout: Self.wait, else: "Closet didn't open") {
            closetTab.exists && closetTab.isSelected
        }
        expectTour("Add your clothes", step: 1, of: 3, in: app)
        next(to: "Find a piece", step: 2, of: 3, in: app)
        skip(in: app)

        // Replay Profile's own tour from App tours, then a screen under More screen tours.
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        openAppTours(in: app)
        openMoreScreenTours(in: app)
        let appTours = app.switches["appTours.showTips"]
        tap("appTours.profile", in: app) { !appTours.exists }
        expectTour("Your name on the sign", step: 1, of: 3, in: app)
        skip(in: app)
        openAppTours(in: app)
        openMoreScreenTours(in: app)
        tap("appTours.help", in: app, showing: app.navigationBars["Help"])
        expectTour("Find a simple answer", step: 1, of: 2, in: app)
        skip(in: app)
        app.goBack(from: "Help", to: "Profile", timeout: Self.wait)
        // One of the Stage A audit's tours, on a screen Profile opens itself.
        openAppTours(in: app)
        openMoreScreenTours(in: app)
        tap("appTours.deleteData", in: app, showing: app.navigationBars["Delete my data"])
        expectTour("What goes", step: 1, of: 2, in: app)
        // Its last step scrolls down to the button. When the tour ends the page goes back up, so
        // the title isn't left half under the bar (QA, October 2026).
        next(to: "It asks once more", step: 2, of: 2, in: app)
        app.buttons["tour.next"].tapUntilGone(timeout: Self.wait)
        expectTitleClear("Delete my data", in: app)
        app.goBack(from: "Delete my data", to: "Profile", timeout: Self.wait)

        // Tips on: a screen she hasn't seen shows its tour by itself.
        openAppTours(in: app)
        // A second tap would turn it off again, so it's tapped again only if it didn't turn on.
        tips.tapUntil(timeout: Self.wait, else: "Tips didn't turn on") { tips.exists && tips.value as? String == "1" }
        closeSheet(in: app)
        tap("profile.privacy", in: app, showing: app.navigationBars["Privacy and terms"])
        expectTour("You choose what to share", step: 1, of: 2, in: app)
        skip(in: app)
        app.goBack(from: "Privacy and terms", to: "Profile", timeout: Self.wait)
        tap("profile.privacy", in: app, showing: app.navigationBars["Privacy and terms"])
        expectNoTour(in: app)
        app.goBack(from: "Privacy and terms", to: "Profile", timeout: Self.wait)

        // Reset all tips: the seen one shows again.
        openAppTours(in: app)
        tap("appTours.reset", in: app, showing: app.staticTexts["appTours.note"])
        closeSheet(in: app)
        tap("profile.privacy", in: app, showing: app.navigationBars["Privacy and terms"])
        expectTour("You choose what to share", step: 1, of: 2, in: app)
    }

    // MARK: Helpers

    @MainActor
    private func expectTour(
        _ title: String, step: Int, of count: Int, in app: XCUIApplication, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let words = app.descendants(matching: .any)["tour.text"]
        let predicate = NSPredicate(format: "label BEGINSWITH %@", "Quick tour, step \(step) of \(count). \(title)")
        XCTAssertTrue(
            words.waitUntil(predicate, timeout: Self.wait),
            "Expected \(title), step \(step) of \(count): \(words.label)", file: file, line: line)
    }

    @MainActor
    private func expectNoTour(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // Long enough for a tour that would start once the screen has loaded.
        let card = app.descendants(matching: .any)["tour.card"]
        XCTAssertFalse(card.waitUntilExists(timeout: 2), "A tour showed", file: file, line: line)
    }

    /// The page's own title is back below the navigation bar once the page has stopped moving.
    @MainActor
    private func expectTitleClear(
        _ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let bar = app.navigationBars[title]
        let heading = app.scrollViews.staticTexts[title].firstMatch
        XCTAssertTrue(heading.waitUntilExists(timeout: Self.wait), "No title on the page", file: file, line: line)
        XCTAssertTrue(
            waitUntilTrue(timeout: Self.wait) { heading.frame.minY >= bar.frame.maxY - 1 },
            "The title is under the bar: \(heading.frame), bar \(bar.frame)", file: file, line: line)
    }

    @MainActor
    private func skip(in app: XCUIApplication) {
        app.buttons["tour.skip"].tapUntilGone(timeout: Self.wait)
    }

    /// Taps the tour's Next until the card shows the step after.
    @MainActor
    private func next(
        to title: String, step: Int, of count: Int, in app: XCUIApplication, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let words = app.descendants(matching: .any)["tour.text"]
        let predicate = NSPredicate(format: "label BEGINSWITH %@", "Quick tour, step \(step) of \(count). \(title)")
        app.buttons["tour.next"].tapUntil(
            timeout: Self.wait, else: "Next didn't move on to \(title)", file: file, line: line
        ) { words.exists && predicate.evaluate(with: words) }
    }

    @MainActor
    private func openAppTours(in app: XCUIApplication) {
        tap("profile.appTours", in: app, showing: app.switches["appTours.showTips"])
    }

    /// Opens More screen tours. The button opens and closes the list, so it's tapped again only
    /// if the list didn't open.
    @MainActor
    private func openMoreScreenTours(in app: XCUIApplication) {
        let more = app.buttons["appTours.more"]
        tap("appTours.more", in: app) { more.exists && more.value as? String == "Open" }
    }

    @MainActor
    private func closeSheet(in app: XCUIApplication) {
        let close = app.buttons["Close"].firstMatch
        close.tapUntilGone(timeout: Self.wait)
    }

    /// Taps a button by identifier, scrolling to find it if it's off the screen (Closet stays
    /// scrolled down after Recently deleted, so Suitcases is above), until `effect` holds (see
    /// `XCUIElement.tapUntil(timeout:_:)`).
    @MainActor
    private func tap(
        _ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line,
        until effect: @escaping @MainActor () -> Bool
    ) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(identifier)", file: file, line: line)
        app.scrollUntilHittable(button, up: 16, down: 16)
        button.tapUntil(timeout: Self.wait, else: "\(identifier) didn't do its job", file: file, line: line, effect)
    }

    /// Taps a button by identifier until `next` appears.
    @MainActor
    private func tap(
        _ identifier: String, in app: XCUIApplication, showing next: XCUIElement, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tap(identifier, in: app, file: file, line: line) { next.exists }
    }

    @MainActor
    private func waitForValue(_ value: String, of element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return element.waitUntil(predicate, timeout: Self.wait)
    }
}
