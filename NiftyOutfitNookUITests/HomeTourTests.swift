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
    static let wait: TimeInterval = 15

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
                app.buttons["tour.back"].tapWhenHittable(timeout: Self.wait)
                XCTAssertTrue(waitForLabel(of: words, containing: "step 1 of 4"), words.label)
                app.buttons["tour.next"].tapWhenHittable(timeout: Self.wait)
                XCTAssertTrue(waitForLabel(of: words, containing: "step 2 of 4"), words.label)
            }
            if index < steps.count - 1 {
                XCTAssertEqual(app.buttons["tour.next"].label, "Next")
                app.buttons["tour.next"].tapWhenHittable(timeout: Self.wait)
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
        app.buttons["tour.next"].tapWhenHittable(timeout: Self.wait)
        let words = app.descendants(matching: .any)["tour.text"]
        XCTAssertTrue(waitForLabel(of: words, containing: "step 2 of 4"), words.label)
        app.buttons["tour.skip"].tapUntilGone(timeout: Self.wait)

        XCTAssertTrue(app.buttons["home.laptop"].waitUntilHittable(timeout: Self.wait))
        XCTAssertTrue(app.navigationBars["Home"].exists, "Skip opened something")
        app.buttons["home.helpDrawer"].tapWhenHittable(timeout: Self.wait)
        app.goBack(from: "Help", to: "Home", timeout: Self.wait)
        XCTAssertFalse(app.descendants(matching: .any)["tour.card"].exists, "The tour came back")
    }

    /// Tapping the highlighted control ends the tour and does what the control does, once.
    @MainActor
    func testTappingTheHighlightedControlOpensIt() {
        let app = launch()
        let target = app.buttons["tour.target"]
        XCTAssertTrue(target.waitForExistence(timeout: Self.wait))
        XCTAssertEqual(target.label, "Laptop: Style Me")
        target.tapWhenHittable(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Style Me"].waitForExistence(timeout: Self.wait), "Style Me didn't open")
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
        XCTAssertTrue(tour.waitForExistence(timeout: Self.wait), "The tour isn't exposed as modal")

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
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        XCTAssertTrue(waitForLabel(of: words, containing: "step 1 of 4"), words.label)
        XCTAssertTrue(app.navigationBars["Home"].exists)
        // Escape and the VoiceOver escape gesture can't be sent from here: on the iOS 26.5
        // simulator `typeKey(.escape)` reached neither `.keyboardShortcut(.cancelAction)` nor a
        // focused `.onKeyPress(.escape)` (tried in 16a). Skip's keyboard shortcut and the
        // VoiceOver escape action call the same skip as the Skip button (docs/tours.md).
    }

    /// At the largest text size Home is the banner and large rows, and the tour walks them in
    /// the same order, in their own words, scrolling each into view.
    @MainActor
    func testTheTourAtTheLargestTextSize() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let words = app.descendants(matching: .any)["tour.text"]
        let titles = ["Style Me", "Your closet", "Your suitcase", "That is you"]
        for (index, title) in titles.enumerated() {
            XCTAssertTrue(
                waitForLabel(of: words, containing: "Quick tour, step \(index + 1) of 4. \(title)."), words.label)
            let next = app.buttons["tour.next"]
            XCTAssertTrue(next.waitUntilHittable(timeout: Self.wait), "Next is out of reach on step \(index + 1)")
            XCTAssertTrue(app.buttons["tour.skip"].isHittable, "Skip is out of reach on step \(index + 1)")
            next.tap()
        }
        XCTAssertTrue(words.waitForNonExistence(timeout: Self.wait))
        XCTAssertTrue(app.buttons["home.laptop"].waitForExistence(timeout: Self.wait))
    }

    /// `-tour off` keeps the tour from starting by itself; `-tour off,home` still starts it.
    @MainActor
    func testTheDebugFlag() {
        let quiet = XCUIApplication()
        quiet.launchArguments = UITestLaunch.skipOnboarding + ["-tour", "off", "-fixtures", "demo"]
        quiet.launch()
        XCTAssertTrue(quiet.buttons["home.laptop"].waitUntilHittable(timeout: Self.wait))
        XCTAssertFalse(quiet.descendants(matching: .any)["tour.card"].waitForExistence(timeout: 3))

        let forced = launch(tour: "off,home")
        XCTAssertTrue(forced.buttons["tour.skip"].exists)
    }

    // MARK: Helpers

    /// Launches with Home's tour starting as on a fresh install, and waits for its card. Tips are
    /// off, so the other screens' tours (Phase 16b, `ScreenToursTests`) stay out of the way when
    /// these tests leave Home.
    @MainActor
    private func launch(tour: String = "off,home", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.skipOnboarding + ["-tour", tour, "-fixtures", "demo"] + extra
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["tour.card"].waitForExistence(timeout: Self.wait), "The tour didn't start")
        return app
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: Self.wait) == .completed
    }
}
