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
        search.typeTextAndWait("navy pants\n", timeout: Self.wait)
        tap("closet.garment.g-navy-trousers", in: app, showing: app.buttons["garment.styleWithThis"])
        tap("garment.styleWithThis", in: app, showing: app.buttons["styleWithThis.makeYourOwnLook"])
        tap("styleWithThis.makeYourOwnLook", in: app, showing: app.navigationBars["Make your own look"])

        // It starts with the trousers; one piece isn't a look yet.
        XCTAssertTrue(app.buttons["builder.remove.g-navy-trousers"].waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(app.buttons["builder.save"].isEnabled)

        // Add a piece: the pink shirt, from the picker's Tops. On CI a tap on Add a piece was once
        // lost and the picker never came, so tap once more if it doesn't open.
        let tops = app.buttons["closet.filter.kind.top"]
        tap("builder.add", in: app, showing: tops)
        tap("closet.filter.kind.top", in: app) { tops.exists && tops.isSelected }
        tap("picker.garment.g-pink-blouse", in: app, showing: app.buttons["builder.remove.g-pink-blouse"])

        // Name it and save.
        let name = app.descendants(matching: .any)["field.builder.name"]
        XCTAssertTrue(name.waitUntilExists(timeout: Self.wait))
        name.tapUntilFocused(timeout: Self.wait)
        name.typeTextAndWait("Friday pink\n", timeout: Self.wait)
        // The same for Save look. Once saved, the button says Saved and can't be tapped again.
        let save = app.buttons["builder.save"]
        tap("builder.save", in: app) { save.exists && save.label.contains("Saved") }
    }

    /// LR-08.4: a half-built look left when the app closed (seeded by `draft=look`) is offered
    /// from "+ Make your own", and Resume brings it back.
    @MainActor
    func testAHalfBuiltLookIsOfferedAfterARelaunch() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo:draft=look"]
        app.launch()
        app.tabBars.firstMatch.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        tap("savedLooks.makeYourOwn", in: app, showing: app.navigationBars["Make your own look"])
        let message = app.staticTexts["builder.draft.message"]
        XCTAssertTrue(message.waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(message.label.contains("Pink for Friday"), message.label)
        tap("builder.draft.resume", in: app, showing: app.buttons["builder.remove.g-pink-blouse"])
        XCTAssertTrue(app.buttons["builder.remove.g-navy-trousers"].exists)
        XCTAssertTrue(app.buttons["builder.save"].isEnabled)
    }

    // MARK: Helpers

    /// Taps a button by identifier, scrolling up to find it if it's below the screen, until
    /// `effect` holds (see `XCUIElement.tapUntil(timeout:_:)`).
    @MainActor
    private func tap(
        _ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line,
        until effect: @escaping @MainActor () -> Bool
    ) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(identifier)", file: file, line: line)
        app.scrollUntilHittable(button, up: 12)
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
}
