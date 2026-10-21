import XCTest

/// Home's quick tour (Phase 16a, PRD §7.8): it starts by itself the first time Home shows,
/// walks the laptop, the wardrobe, the suitcase and the name sign, and ends with Start styling,
/// Skip, Escape or a tap on the highlighted control.
///
/// UI tests can't run VoiceOver. They check what XCUITest can see of it: the tour is modal (an
/// alert to XCUITest) with the card's words first, nothing under the dim can be tapped, each
/// step names the highlighted control, and the highlighted control is itself a button.
/// Moving VoiceOver focus, the escape gesture, Escape on a keyboard and focus going back to the
/// control need a check by hand (see `docs/tours.md`).
final class HomeTourTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    /// Next through all four steps in order, Back on the way, then Start styling. Each step
    /// lights up its control, and the tour doesn't come back when Home shows again.
    @MainActor
    func testCompletingTheTour() {
        let app = launch()
        let steps: [(title: String, control: String)] = [
            ("Style Me", "home.laptop"),
            ("Your closet", "home.wardrobe"),
            ("Packing from", "home.suitcase"),
            ("That’s you", "home.nameSign"),
        ]
        XCTAssertFalse(app.buttons["tour.back"].exists, "Back on the first step")
        for (index, step) in steps.enumerated() {
            let words = app.descendants(matching: .any)["tour.text"]
            XCTAssertTrue(
                waitForLabel(of: words, containing: "Quick tour, step \(index + 1) of 4. \(step.title)."), words.label)
            XCTAssertTrue(words.label.contains("Highlighted: "), "Step \(index + 1) doesn't name its control")
            if index == 1 {
                // Back goes to the step before, and Next comes back.
                tap("tour.back", in: app, until: "step 1 of 4")
                tap("tour.next", in: app, until: "step 2 of 4")
            }
            if index < steps.count - 1 {
                XCTAssertEqual(app.buttons["tour.next"].label, "Next")
                tap("tour.next", in: app, until: "step \(index + 2) of 4")
            }
        }
        let finish = app.buttons["tour.next"]
        XCTAssertEqual(finish.label, "Start styling")
        finish.tapUntilGone(timeout: Self.wait)

        // The room works again, and the tour doesn't come back on its own.
        XCTAssertTrue(app.buttons["home.laptop"].waitUntilHittable(timeout: Self.wait), "The room is still covered")
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        app.tabBars.firstMatch.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(app.buttons["home.laptop"].waitUntilHittable(timeout: Self.wait))
        XCTAssertFalse(app.descendants(matching: .any)["tour.card"].exists, "The tour came back")
    }

    /// Skip on step 2 ends the tour for good this session; nothing opened.
    @MainActor
    func testSkippingTheTour() {
        let app = launch()
        tap("tour.next", in: app, until: "step 2 of 4")
        app.buttons["tour.skip"].tapUntilGone(timeout: Self.wait)

        XCTAssertTrue(app.buttons["home.laptop"].waitUntilHittable(timeout: Self.wait))
        XCTAssertTrue(app.navigationBars["Home"].exists, "Skip opened something")
        app.buttons["home.helpDrawer"].tapUntil(app.navigationBars["Help"], appears: Self.wait)
        app.goBack(from: "Help", to: "Home", timeout: Self.wait)
        XCTAssertFalse(app.descendants(matching: .any)["tour.card"].exists, "The tour came back")
    }

    /// Tapping the highlighted control ends the tour and does what the control does, once.
    @MainActor
    func testTappingTheHighlightedControlOpensIt() {
        let app = launch()
        let target = app.buttons["tour.target"]
        XCTAssertTrue(target.waitUntilExists(timeout: Self.wait))
        XCTAssertEqual(target.label, "Laptop: Style Me")
        target.tapUntil(app.navigationBars["Style Me"], appears: Self.wait)
        XCTAssertFalse(app.descendants(matching: .any)["tour.card"].exists)
        app.goBack(from: "Style Me", to: "Home", timeout: Self.wait)
        XCTAssertFalse(app.descendants(matching: .any)["tour.card"].exists, "The tour came back")
    }

    /// While the tour shows it's modal: XCUITest sees it as an alert, its card's words come
    /// first in it, and the room and tab bar under the dim can't be tapped.
    @MainActor
    func testTheTourIsModal() {
        let app = launch()
        let tour = app.alerts["tour"]
        XCTAssertTrue(tour.waitUntilExists(timeout: Self.wait), "The tour isn't exposed as modal")

        // Inside the tour the card's words come before everything else. Queries return elements
        // breadth first, so the order is read from the tree XCUITest prints, which is the order
        // the app exposes.
        let tree = tour.debugDescription
        let order = ["tour.text", "tour.skip", "tour.next", "tour.target"].map {
            tree.range(of: "identifier: '\($0)'")?.lowerBound
        }
        XCTAssertFalse(order.contains(nil), tree)
        XCTAssertEqual(order.compactMap(\.self), order.compactMap(\.self).sorted(), "Not read card first: \(tree)")
        let words = app.descendants(matching: .any)["tour.text"]
        XCTAssertTrue(words.label.hasPrefix("Quick tour, step 1 of 4. Style Me."), words.label)
        XCTAssertTrue(words.label.hasSuffix("Highlighted: Laptop: Style Me."), words.label)

        // The dim covers the room and the tab bar; the tour's own buttons are in reach.
        XCTAssertFalse(app.buttons["home.wardrobe"].isHittable, "The room can be tapped through the tour")
        XCTAssertFalse(app.tabBars.firstMatch.buttons["Closet"].isHittable, "The tab bar can be tapped")
        for identifier in ["tour.skip", "tour.next", "tour.target"] {
            XCTAssertTrue(app.buttons[identifier].isHittable, "\(identifier) can't be reached")
        }

        // A tap on the dim does nothing.
        let dim = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1))
        dim.tap()  // tap-unconfirmed: the test checks that nothing happens
        XCTAssertTrue(waitForLabel(of: words, containing: "step 1 of 4"), words.label)
        XCTAssertTrue(app.navigationBars["Home"].exists)
        // Escape and the VoiceOver escape gesture can't be sent from here: on the iOS 26.5
        // simulator `typeKey(.escape)` reached neither `.keyboardShortcut(.cancelAction)` nor a
        // focused `.onKeyPress(.escape)` (tried in 16a). Command-period does reach the cancel
        // action, so `IPadKeyboardTests` skips a tour with it. Skip's keyboard shortcut and the
        // VoiceOver escape action call the same skip as the Skip button (docs/tours.md).
    }

    /// What VoiceOver meets on every step, as far as XCUITest can see it (Stage A device
    /// substitutes; nobody can run VoiceOver here). On each step of Home's tour and of Closet's,
    /// the first element in the tour is the card's words, which name the step and the
    /// highlighted control; then Back (from step 2), Skip and Next; then the highlighted control.
    /// Nothing from the screen under the dim is inside the tour.
    @MainActor
    func testTheCardComesFirstOnEveryStep() {
        let app = launch()
        assertEveryStepReadsCardFirst(steps: 4, in: app, under: ["home.wardrobe", "home.laptop"])
        app.terminate()

        let closet = launch(tour: "off,closet", openCloset: true)
        assertEveryStepReadsCardFirst(steps: 3, in: closet, under: ["closet.addPiece"])
    }

    /// At the largest text size Home is the banner and large rows, and the tour walks them in
    /// the same order, in their own words, scrolling each into view.
    ///
    /// Merges and nightly only, with the other AX5 checks: `TourCenterTests` has the large-text
    /// tour's steps and words, and the AX5 audit sweep checks Home.
    @MainActor
    func testTheTourAtTheLargestTextSize() throws {
        try skipOnPullRequests("TourCenterTests covers the large-text steps.")
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let words = app.descendants(matching: .any)["tour.text"]
        let titles = ["Style Me", "Your closet", "Your suitcase", "That is you"]
        for (index, title) in titles.enumerated() {
            XCTAssertTrue(
                waitForLabel(of: words, containing: "Quick tour, step \(index + 1) of 4. \(title)."), words.label)
            let next = app.buttons["tour.next"]
            XCTAssertTrue(next.waitUntilHittable(timeout: Self.wait), "Next is out of reach on step \(index + 1)")
            XCTAssertTrue(app.buttons["tour.skip"].isHittable, "Skip is out of reach on step \(index + 1)")
            // The words move on to the next step, or the tour closes after the last.
            let movedOn = next.tapUntil(timeout: Self.wait) {
                !words.exists || !words.label.contains("step \(index + 1) of 4")
            }
            XCTAssertTrue(movedOn, "Next didn't move on from step \(index + 1)")
        }
        XCTAssertTrue(words.waitUntilGone(timeout: Self.wait))
        XCTAssertTrue(app.buttons["home.laptop"].waitUntilExists(timeout: Self.wait))
    }

    // MARK: Helpers

    /// Launches with Home's tour starting as on a fresh install, and waits for its card. Tips are
    /// off, so the other screens' tours (Phase 16b, `ScreenToursTests`) stay out of the way when
    /// these tests leave Home.
    @MainActor
    private func launch(tour: String = "off,home", extra: [String] = [], openCloset: Bool = false)
        -> XCUIApplication
    {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.skipOnboarding + ["-tour", tour, "-fixtures", "demo"] + extra
        app.launch()
        if openCloset {
            app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["tour.card"].waitUntilExists(timeout: Self.wait), "The tour didn't start")
        return app
    }

    /// Taps a tour button until the card's words contain `text` (a step such as "step 2 of 4").
    @MainActor
    private func tap(
        _ identifier: String, in app: XCUIApplication, until text: String, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let words = app.descendants(matching: .any)["tour.text"]
        app.buttons[identifier].tapUntil(
            timeout: Self.wait, else: "\(identifier) didn't move the tour to \(text)", file: file, line: line
        ) { words.exists && words.label.contains(text) }
    }

    /// Walks a tour's steps with Next, checking on each one that the tour, which XCUITest sees
    /// as an alert, starts with the card's words for that step and keeps its buttons and the
    /// highlighted control after them, and that none of `under` (controls on the screen under
    /// the dim) is in it. Queries return elements breadth first, so the order is read from the
    /// tree XCUITest prints, which is the order the app exposes.
    @MainActor
    private func assertEveryStepReadsCardFirst(
        steps: Int, in app: XCUIApplication, under: [String], file: StaticString = #filePath, line: UInt = #line
    ) {
        let tour = app.alerts["tour"]
        let words = app.descendants(matching: .any)["tour.text"]
        for step in 1...steps {
            XCTAssertTrue(
                waitForLabel(of: words, containing: "step \(step) of \(steps)"), "No step \(step)", file: file,
                line: line)
            XCTAssertTrue(tour.waitUntilExists(timeout: Self.wait), "The tour isn't modal", file: file, line: line)
            let tree = tour.debugDescription
            // The first element below the tour's own line that VoiceOver could land on, the
            // first with a label (the card itself is an unlabelled container).
            let first = tree.split(separator: "\n").dropFirst().first { $0.contains("label: '") }
            XCTAssertTrue(
                first?.contains("identifier: 'tour.text'") == true, "Step \(step) doesn't start on the card: \(tree)",
                file: file, line: line)
            var order = ["tour.text", "tour.skip", "tour.next", "tour.target"]
            if step > 1 { order.insert("tour.back", at: 1) }
            let places = order.map { tree.range(of: "identifier: '\($0)'")?.lowerBound }
            XCTAssertFalse(
                places.contains(nil), "Step \(step) is missing one of \(order): \(tree)", file: file, line: line)
            XCTAssertEqual(
                places.compactMap(\.self), places.compactMap(\.self).sorted(),
                "Step \(step) reads out of order: \(tree)",
                file: file, line: line)
            for identifier in under {
                XCTAssertFalse(
                    tree.contains("identifier: '\(identifier)'"), "\(identifier) is inside the tour on step \(step)",
                    file: file, line: line)
            }
            XCTAssertTrue(
                words.label.contains("Highlighted: "), "Step \(step) doesn't name its control", file: file, line: line)
            if step < steps {
                tap("tour.next", in: app, until: "step \(step + 1) of \(steps)", file: file, line: line)
            }
        }
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return element.waitUntil(predicate, timeout: Self.wait)
    }
}
