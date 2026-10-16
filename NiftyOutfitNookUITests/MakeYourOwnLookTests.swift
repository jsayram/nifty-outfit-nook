import XCTest

/// Make your own look (Phase 11, LR-08.3, LR-08.4): from a garment's Style with this, and a
/// half-built look offered again after a relaunch from Saved Looks' "+ Make your own".
final class MakeYourOwnLookTests: XCTestCase {
    static let wait: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
    }

    /// Navy dress pants, Style with this, Make my own look: add a top from the picker, name the
    /// look and save it.
    @MainActor
    func testMakeYourOwnLookFromGarmentDetailAndSave() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo"]
        app.launch()
        app.tabBars.firstMatch.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        let search = app.searchFields["Search your closet"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.wait))
        search.tap()
        search.typeText("navy pants\n")
        tap("closet.garment.g-navy-trousers", in: app)
        tap("garment.styleWithThis", in: app)
        tap("styleWithThis.makeYourOwnLook", in: app)
        XCTAssertTrue(app.navigationBars["Make your own look"].waitForExistence(timeout: Self.wait))

        // It starts with the trousers; one piece isn't a look yet.
        XCTAssertTrue(app.buttons["builder.remove.g-navy-trousers"].waitForExistence(timeout: Self.wait))
        XCTAssertFalse(app.buttons["builder.save"].isEnabled)

        // Add a piece: the pink shirt, from the picker's Tops.
        tap("builder.add", in: app)
        tap("closet.filter.kind.top", in: app)
        tap("picker.garment.g-pink-blouse", in: app)
        XCTAssertTrue(app.buttons["builder.remove.g-pink-blouse"].waitForExistence(timeout: Self.wait))

        // Name it and save.
        let name = app.descendants(matching: .any)["field.builder.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.wait))
        name.tap()
        name.typeText("Friday pink\n")
        let save = app.buttons["builder.save"]
        tap("builder.save", in: app)
        XCTAssertTrue(waitForLabel(of: save, containing: "Saved"), save.label)
    }

    /// LR-08.4: a half-built look left when the app closed (seeded by `draft=look`) is offered
    /// from "+ Make your own", and Resume brings it back.
    @MainActor
    func testAHalfBuiltLookIsOfferedAfterARelaunch() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo:draft=look"]
        app.launch()
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        tap("savedLooks.makeYourOwn", in: app)
        XCTAssertTrue(app.navigationBars["Make your own look"].waitForExistence(timeout: Self.wait))
        let message = app.staticTexts["builder.draft.message"]
        XCTAssertTrue(message.waitForExistence(timeout: Self.wait))
        XCTAssertTrue(message.label.contains("Pink for Friday"), message.label)
        tap("builder.draft.resume", in: app)
        XCTAssertTrue(app.buttons["builder.remove.g-pink-blouse"].waitForExistence(timeout: Self.wait))
        XCTAssertTrue(app.buttons["builder.remove.g-navy-trousers"].exists)
        XCTAssertTrue(app.buttons["builder.save"].isEnabled)
    }

    // MARK: Helpers

    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: Self.wait), "No button \(identifier)")
        var swipes = 0
        while !button.isHittable && swipes < 6 {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        button.tapWhenHittable(timeout: Self.wait)
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [changed], timeout: Self.wait) == .completed
    }
}
