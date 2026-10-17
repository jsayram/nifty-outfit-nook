import XCTest

/// Make your own look (Phase 11, LR-08.3, LR-08.4): from a garment's Style with this, and a
/// half-built look offered again after a relaunch from Saved Looks' "+ Make your own".
final class MakeYourOwnLookTests: XCTestCase {
    static let wait = uiTestWait

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
        XCTAssertTrue(search.waitUntilExists(timeout: Self.wait))
        search.tapUntilFocused(timeout: Self.wait)
        search.typeText("navy pants\n")
        tap("closet.garment.g-navy-trousers", in: app)
        tap("garment.styleWithThis", in: app)
        tap("styleWithThis.makeYourOwnLook", in: app)
        XCTAssertTrue(app.navigationBars["Make your own look"].waitUntilExists(timeout: Self.wait))

        // It starts with the trousers; one piece isn't a look yet.
        XCTAssertTrue(app.buttons["builder.remove.g-navy-trousers"].waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(app.buttons["builder.save"].isEnabled)

        // Add a piece: the pink shirt, from the picker's Tops. On CI a tap on Add a piece was once
        // lost and the picker never came, so tap once more if it doesn't open.
        let tops = app.buttons["closet.filter.kind.top"]
        for _ in 0..<2 {
            tap("builder.add", in: app)
            if tops.waitUntilExists(timeout: Self.wait) { break }
        }
        tap("closet.filter.kind.top", in: app)
        tap("picker.garment.g-pink-blouse", in: app)
        XCTAssertTrue(app.buttons["builder.remove.g-pink-blouse"].waitUntilExists(timeout: Self.wait))

        // Name it and save.
        let name = app.descendants(matching: .any)["field.builder.name"]
        XCTAssertTrue(name.waitUntilExists(timeout: Self.wait))
        name.tapUntilFocused(timeout: Self.wait)
        name.typeText("Friday pink\n")
        // The same for Save look. Once saved, the button says Saved and can't be tapped again.
        let save = app.buttons["builder.save"]
        for _ in 0..<2 {
            tap("builder.save", in: app)
            if waitForLabel(of: save, containing: "Saved") { break }
        }
        XCTAssertTrue(save.label.contains("Saved"), save.label)
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
        XCTAssertTrue(app.navigationBars["Make your own look"].waitUntilExists(timeout: Self.wait))
        let message = app.staticTexts["builder.draft.message"]
        XCTAssertTrue(message.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(message.label.contains("Pink for Friday"), message.label)
        tap("builder.draft.resume", in: app)
        XCTAssertTrue(app.buttons["builder.remove.g-pink-blouse"].waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(app.buttons["builder.remove.g-navy-trousers"].exists)
        XCTAssertTrue(app.buttons["builder.save"].isEnabled)
    }

    // MARK: Helpers

    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(identifier)")
        app.scrollUntilHittable(button, up: 12)
        button.tapWhenHittable(timeout: Self.wait)
    }

    @MainActor
    private func waitForLabel(of element: XCUIElement, containing text: String) -> Bool {
        return element.waitUntil(NSPredicate(format: "label CONTAINS %@", text), timeout: Self.wait)
    }
}
