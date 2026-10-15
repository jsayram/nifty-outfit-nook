import XCTest

/// Home's furniture (RD-01.2): each piece opens its screen, and Back returns to the room.
final class HomeTests: XCTestCase {
    /// How long to wait for a screen or a change. Waits end as soon as the condition holds, so
    /// this only matters on a slow machine: on CI a back tap once took more than 5 seconds to land.
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testEachPieceOfFurnitureOpensItsScreenAndComesBack() {
        let app = launch("demo")

        // Pushed screens, by the furniture's identifier and the title they open with.
        let pushed = [
            ("home.laptop", "Style Me"),
            ("home.occasion", "Style Me"),
            ("home.helpDrawer", "Help"),
            ("home.feedbackDrawer", "Send feedback"),
            ("home.privacyDrawer", "Privacy and terms"),
            ("home.nameSign", "Profile"),
            ("home.profile", "Profile"),
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

        // The wardrobe and the shelf switch tabs.
        let tabBar = app.tabBars.firstMatch

        // The suitcase opens Suitcases on the Closet tab, where Suitcases lives (Phase 13).
        let suitcase = app.buttons["home.suitcase"]
        reveal(suitcase, in: app)
        suitcase.tap()
        XCTAssertTrue(app.navigationBars["Suitcases"].waitForExistence(timeout: Self.wait), "No Suitcases")
        XCTAssertTrue(tabBar.buttons["Closet"].isSelected)
        tabBar.buttons["Home"].tapUntilSelected(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Home"].waitUntilHittable(timeout: Self.wait))

        for (identifier, tab) in [("home.wardrobe", "Closet"), ("home.savedLooks", "Saved Looks")] {
            let control = app.buttons[identifier]
            reveal(control, in: app)
            control.tap()
            XCTAssertTrue(tabBar.buttons[tab].waitForExistence(timeout: Self.wait))
            XCTAssertTrue(tabBar.buttons[tab].isSelected, "\(identifier) didn't switch to \(tab)")
            tabBar.buttons["Home"].tapUntilSelected(timeout: Self.wait)
            XCTAssertTrue(app.navigationBars["Home"].waitUntilHittable(timeout: Self.wait))
        }
    }

    /// The sign and the plates show the sample data, and VoiceOver hears it (RD-01.3, RD-03).
    @MainActor
    func testRoomShowsHerNameAndTheSource() {
        let app = launch("demo")
        XCTAssertTrue(app.buttons["Name sign: Lily"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(app.buttons["Suitcase: Source, Main closet, 17 pieces, Whole closet"].exists)
        XCTAssertTrue(app.buttons["Wardrobe: Closet"].exists)
        XCTAssertTrue(app.staticTexts["Nifty Outfit Nook"].exists)
        app.terminate()

        // A fresh install has no name: the sign shows a neutral word, never a blank (RD-03.2).
        let empty = launch("empty")
        XCTAssertTrue(empty.buttons["Name sign, no name yet"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(empty.buttons["Suitcase: Source, Main closet, Empty, Whole closet"].exists)
    }

    /// RD-11.3 and RD-11.4: with tracking off the faded hamper opens a short sheet. Not now just
    /// closes it; Turn on saves the setting and the hamper fills with the demo's two dirty
    /// pieces without a relaunch.
    @MainActor
    func testHamperSheetTurnsLaundryTrackingOn() {
        let app = launch("demo")
        let hamper = app.buttons["home.hamper"]
        reveal(hamper, in: app)
        XCTAssertEqual(hamper.label, "Hamper: Laundry, Off")

        hamper.tap()
        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: Self.wait), "The laundry sheet didn't open")
        XCTAssertTrue(app.staticTexts["Laundry tracking is off"].exists)
        notNow.tapUntilGone(timeout: Self.wait)
        XCTAssertEqual(hamper.label, "Hamper: Laundry, Off")

        reveal(hamper, in: app)
        hamper.tap()
        let turnOn = app.buttons["laundryTracking.turnOn"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: Self.wait))
        // The sheet closes once tracking is on.
        turnOn.tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(
            waitForLabel(of: hamper, containing: "Hamper: Laundry, 2 to wash"),
            "The hamper didn't update: \(hamper.label)")
        // Now it's a real Laundry control.
        reveal(hamper, in: app)
        hamper.tap()
        XCTAssertTrue(app.navigationBars["Laundry"].waitForExistence(timeout: Self.wait))
    }

    /// RD-01.4 and LR-04: the window shows the forced weather, and Style Me's Weather row and
    /// sheet work. Each choice shows on the row; a new Style Me starts on today's weather again.
    @MainActor
    func testWeatherWindowAndStyleMeWeatherChoices() {
        let app = launch("demo:weather=snow")
        let window = app.descendants(matching: .any)["home.window"]
        XCTAssertTrue(window.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(waitForLabel(of: window, containing: "Window: Snow"), "The window shows \(window.label)")

        let laptop = app.buttons["home.laptop"]
        reveal(laptop, in: app)
        laptop.tap()
        let row = app.buttons["styleMe.weather"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(waitForLabel(of: row, containing: "30° and snow"), row.label)
        XCTAssertTrue(row.label.contains("Your looks are picked for today’s weather."), row.label)

        for (option, value) in [("weather.indoors", "Indoors"), ("weather.ignore", "Ignored")] {
            row.tap()
            let choice = app.buttons[option]
            XCTAssertTrue(choice.waitForExistence(timeout: Self.wait), "No \(option) in the sheet")
            XCTAssertTrue(app.buttons["weather.useToday"].isSelected || option == "weather.ignore")
            choice.tap()
            XCTAssertTrue(choice.waitForNonExistence(timeout: Self.wait), "Choosing should close the sheet")
            XCTAssertTrue(waitForLabel(of: row, containing: value), "\(option): \(row.label)")
        }
        // The sheet marks the current choice.
        row.tap()
        XCTAssertTrue(app.buttons["weather.ignore"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(app.buttons["weather.ignore"].isSelected)
        XCTAssertFalse(app.buttons["weather.useToday"].isSelected)
        app.buttons["weather.useToday"].tap()
        XCTAssertTrue(waitForLabel(of: row, containing: "30° and snow"), row.label)

        // The choice is for one request: leaving and coming back starts on today's weather.
        row.tap()
        app.buttons["weather.indoors"].tap()
        XCTAssertTrue(waitForLabel(of: row, containing: "Indoors"), row.label)
        app.goBack(from: "Style Me", to: "Home", timeout: Self.wait)
        reveal(laptop, in: app)
        laptop.tap()
        XCTAssertTrue(row.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(waitForLabel(of: row, containing: "30° and snow"), row.label)
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [changed], timeout: Self.wait) == .completed
    }

    @MainActor
    private func launch(_ fixtures: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-fixtures", fixtures]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        return app
    }

    /// On a short phone the room scrolls; swipe up, then down, until the control can be tapped.
    @MainActor
    private func reveal(
        _ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: Self.wait), "Missing \(element)", file: file, line: line)
        for _ in 0..<3 where !element.isHittable {
            app.swipeUp(velocity: .slow)
        }
        for _ in 0..<3 where !element.isHittable {
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(element.isHittable, "Can't reach \(element)", file: file, line: line)
    }
}
