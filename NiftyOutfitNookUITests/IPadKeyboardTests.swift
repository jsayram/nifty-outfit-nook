import XCTest

/// Hardware keyboard shortcuts on iPad (Stage A device substitutes, 17 October 2026): Command-F
/// puts the keyboard in Closet's and Saved Looks' search, and Cancel (Escape, or Command-period)
/// closes the top sheet and skips a quick tour.
///
/// XCUITest's Escape key reaches the app (it ends editing in a text field) but never triggers a
/// SwiftUI keyboard shortcut on the iOS 26.5 simulator, whether `.cancelAction` or
/// `.keyboardShortcut(.escape, modifiers: [])`; 15b and 16a found the same. Command-period
/// triggers `.cancelAction` too, so these press it to check the shortcut is wired. Escape itself
/// is on the device checklist in `docs/ipad.md`.
final class IPadKeyboardTests: IPadTestCase {
    /// Command-period, which SwiftUI's cancel action answers along with Escape.
    private static let cancel = (key: ".", modifiers: XCUIElement.KeyModifierFlags.command)

    @MainActor
    func testCommandFGoesToSearchOnClosetAndSavedLooks() throws {
        let app = try launch(orientation: .landscapeLeft)
        let tabs = app.tabBars.firstMatch

        tabs.buttons["Closet"].tapUntilSelected(timeout: Self.wait)
        let closetSearch = app.searchFields["Search your closet"]
        XCTAssertTrue(closetSearch.waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(closetSearch.hasKeyboardNow)
        let closetFocused = app.typeKeyUntil("f", modifierFlags: .command, timeout: 5) {
            closetSearch.hasKeyboardNow
        }
        XCTAssertTrue(closetFocused, "Command-F didn't go to Closet's search")
        // She can type straight away. Return searches and puts the keyboard away, so the tab bar
        // is free again (with the field still editing, the keyboard's bar sits over it).
        closetSearch.typeTextAndWait("navy\n", timeout: Self.wait)
        XCTAssertTrue(waitUntilTrue(timeout: Self.wait) { !closetSearch.hasKeyboardNow }, "Return kept the keyboard")

        tabs.buttons["Saved Looks"].tapUntilSelected(timeout: Self.wait)
        let looksSearch = app.searchFields["Search your looks"]
        XCTAssertTrue(looksSearch.waitUntilExists(timeout: Self.wait))
        let looksFocused = app.typeKeyUntil("f", modifierFlags: .command, timeout: 5) {
            looksSearch.hasKeyboardNow
        }
        XCTAssertTrue(looksFocused, "Command-F didn't go to Saved Looks' search")
    }

    @MainActor
    func testCancelClosesTheTopSheet() throws {
        let app = try launch(orientation: .landscapeLeft)
        app.buttons["home.profile"].tapUntil(app.navigationBars["Profile"], appears: Self.wait)
        let choice = app.buttons["profile.preferences.mineAndOneIdea"]
        app.buttons["profile.preferences"].tapUntil(choice, appears: Self.wait)

        let closed = app.typeKeyUntil(Self.cancel.key, modifierFlags: Self.cancel.modifiers, timeout: 5) {
            !choice.exists
        }
        XCTAssertTrue(closed, "Cancel didn't close the Preferences sheet")
        XCTAssertTrue(app.navigationBars["Profile"].waitUntilExists(timeout: Self.wait), "Cancel left Profile")
    }

    @MainActor
    func testCancelSkipsAQuickTour() throws {
        let app = try launch(orientation: .landscapeLeft, tour: "off,home")
        let card = element("tour.card", in: app)
        XCTAssertTrue(card.waitUntilExists(timeout: Self.wait), "Home's tour didn't start")

        let skipped = app.typeKeyUntil(Self.cancel.key, modifierFlags: Self.cancel.modifiers, timeout: 5) {
            !card.exists
        }
        XCTAssertTrue(skipped, "Cancel didn't skip the tour")
        // Skipped, so nothing under it opened.
        XCTAssertTrue(app.buttons["home.laptop"].waitUntilHittable(timeout: Self.wait))
        XCTAssertFalse(app.navigationBars["Style Me"].exists)
    }
}
