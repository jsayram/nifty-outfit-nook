import XCTest

/// Home's other layouts (Phase 5b): at an accessibility text size every action is still a
/// control she can reach and tap (RD-01.5), and held sideways every control is there beside the
/// room, and turning the phone keeps what's open.
final class HomeVariantTests: XCTestCase {
    /// How long to wait for a screen or a change; waits end as soon as the condition holds.
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    /// The largest size, AX5. Every control is reachable by scrolling and opens its place.
    @MainActor
    func testEveryHomeActionIsReachableAtTheLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-fixtures", "demo",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))

        // The large-text layout, not the room: the suitcase is the Source row, read as it reads.
        let source = app.buttons["home.suitcase"]
        XCTAssertTrue(source.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(
            waitForLabel(of: source, containing: "Source: Main closet, 17 pieces, Whole closet"), source.label)

        let pushed = [
            ("home.nameSign", "Profile"),
            ("home.profile", "Profile"),
            ("home.occasion", "Style Me"),
            ("home.laptop", "Style Me"),
            ("home.helpDrawer", "Help"),
            ("home.feedbackDrawer", "Send feedback"),
            ("home.privacyDrawer", "Privacy and terms"),
        ]
        for (identifier, title) in pushed {
            let control = app.buttons[identifier]
            reveal(control, in: app)
            control.tap()
            XCTAssertTrue(
                app.navigationBars[title].waitForExistence(timeout: Self.wait), "\(identifier) didn't open \(title)")
            if identifier == "home.occasion" {
                // The calendar opens Style Me on the Occasion sheet (Phase 10a); close it first.
                XCTAssertTrue(app.buttons["occasion.office"].waitForExistence(timeout: Self.wait), "No Occasion sheet")
                app.buttons["Close"].tapUntilGone(timeout: Self.wait)
                XCTAssertTrue(app.buttons["occasion.office"].waitForNonExistence(timeout: Self.wait))
            }
            app.goBack(from: title, to: "Home", timeout: Self.wait)
        }

        // Laundry tracking is off in the demo, so the Laundry row opens the short sheet.
        let laundry = app.buttons["home.hamper"]
        reveal(laundry, in: app)
        XCTAssertEqual(laundry.label, "Laundry: Off")
        laundry.tap()
        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: Self.wait), "The laundry sheet didn't open")
        // The sheet opens full height here, with Not now below the fold. Only swipe up: a swipe
        // down on a sheet can start closing it. In one CI failure Not now stayed on screen after
        // its tap, following swipes both ways.
        for _ in 0..<6 where !notNow.isHittable {
            app.swipeUp(velocity: .slow)
        }
        notNow.tapUntilGone(timeout: Self.wait)

        // The wardrobe's edge in the banner opens Closet; Saved Looks is the tab.
        let tabBar = app.tabBars.firstMatch
        let wardrobe = app.buttons["home.wardrobe"]
        reveal(wardrobe, in: app)
        // The tap follows the swipes that revealed the wardrobe. On a slow runner the page can
        // still be moving and the tap only stops it, so wait for the tab, and tap once more if
        // it didn't switch.
        let closetTab = tabBar.buttons["Closet"]
        for _ in 0..<2 where !closetTab.isSelected {
            wardrobe.tapWhenHittable(timeout: Self.wait)
            _ = closetTab.waitUntilSelected(timeout: Self.wait)
        }
        XCTAssertTrue(closetTab.isSelected, "The wardrobe didn't switch to Closet")
        tabBar.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        tabBar.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Home"].waitUntilHittable(timeout: Self.wait))

        // The Source row opens Suitcases on the Closet tab (Phase 13).
        reveal(source, in: app)
        source.tap()
        XCTAssertTrue(app.navigationBars["Suitcases"].waitForExistence(timeout: Self.wait), "No Suitcases")
        XCTAssertTrue(tabBar.buttons["Closet"].isSelected)
    }

    /// Sideways, the controls sit beside the room with the title and Profile at their top.
    /// Turning the phone with a screen open keeps it open.
    @MainActor
    func testSidewaysShowsEveryControlAndTurningKeepsWhatIsOpen() {
        XCUIDevice.shared.orientation = .portrait
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-fixtures", "demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))

        XCUIDevice.shared.orientation = .landscapeLeft
        let source = app.buttons["home.suitcase"]
        XCTAssertTrue(waitForLabel(of: source, containing: "Source: Main closet"), source.label)
        XCTAssertFalse(app.navigationBars["Home"].exists, "Sideways, the title moves beside the room")
        for identifier in [
            "home.profile", "home.suitcase", "home.occasion", "home.laptop", "home.hamper", "home.helpDrawer",
            "home.feedbackDrawer", "home.privacyDrawer",
        ] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.exists, "No \(identifier) sideways")
            reveal(control, in: app)
        }

        app.buttons["home.helpDrawer"].tap()
        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: Self.wait))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Help"].waitForExistence(timeout: Self.wait), "Turning the phone closed Help")
        app.goBack(from: "Help", to: "Home", timeout: Self.wait)
        XCTAssertTrue(waitForLabel(of: source, containing: "Suitcase: Source"), "Upright again, it's the room")
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [changed], timeout: Self.wait) == .completed
    }

    /// Scrolls until the control can be tapped: down first, then back up.
    @MainActor
    private func reveal(
        _ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: Self.wait), "Missing \(element)", file: file, line: line)
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp(velocity: .slow)
        }
        for _ in 0..<8 where !element.isHittable {
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(element.isHittable, "Can't reach \(element)", file: file, line: line)
    }
}
