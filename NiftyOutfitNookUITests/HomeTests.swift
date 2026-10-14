import XCTest

/// Home's furniture (RD-01.2): each piece opens its screen, and Back returns to the room.
final class HomeTests: XCTestCase {
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
            ("home.suitcase", "Suitcases"),
            ("home.helpDrawer", "Help"),
            ("home.feedbackDrawer", "Send feedback"),
            ("home.privacyDrawer", "Privacy and terms"),
            ("home.nameSign", "Profile"),
            ("home.profile", "Profile"),
            // Laundry tracking is off by default (RD-11), so the hamper explains it.
            ("home.hamper", "Laundry tracking"),
        ]
        for (identifier, title) in pushed {
            let control = app.buttons[identifier]
            reveal(control, in: app)
            control.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "\(identifier) didn't open \(title)")
            app.navigationBars[title].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5), "No way back from \(title)")
        }

        // The wardrobe and the shelf switch tabs.
        let tabBar = app.tabBars.firstMatch
        for (identifier, tab) in [("home.wardrobe", "Closet"), ("home.savedLooks", "Saved Looks")] {
            let control = app.buttons[identifier]
            reveal(control, in: app)
            control.tap()
            XCTAssertTrue(tabBar.buttons[tab].waitForExistence(timeout: 5))
            XCTAssertTrue(tabBar.buttons[tab].isSelected, "\(identifier) didn't switch to \(tab)")
            tabBar.buttons["Home"].tap()
            XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        }
    }

    /// The sign and the plates show the sample data, and VoiceOver hears it (RD-01.3, RD-03).
    @MainActor
    func testRoomShowsHerNameAndTheSource() {
        let app = launch("demo")
        XCTAssertTrue(app.buttons["Name sign: Lily"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Suitcase: Source, Main closet, 17 pieces, Whole closet"].exists)
        XCTAssertTrue(app.buttons["Wardrobe: Closet"].exists)
        XCTAssertTrue(app.staticTexts["Nifty Outfit Nook"].exists)
        app.terminate()

        // A fresh install has no name: the sign shows a neutral word, never a blank (RD-03.2).
        let empty = launch("empty")
        XCTAssertTrue(empty.buttons["Name sign, no name yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(empty.buttons["Suitcase: Source, Main closet, Empty, Whole closet"].exists)
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
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(element)", file: file, line: line)
        for _ in 0..<3 where !element.isHittable {
            app.swipeUp(velocity: .slow)
        }
        for _ in 0..<3 where !element.isHittable {
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(element.isHittable, "Can't reach \(element)", file: file, line: line)
    }
}
