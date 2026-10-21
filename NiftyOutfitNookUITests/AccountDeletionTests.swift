import XCTest

/// Delete my account (Phase 24c, App Review Guideline 5.1.1(v)), on the fake sign-in and fake
/// backend: signed in, with her own closet of real photo files, she finds Delete my account in
/// Privacy and terms, is asked once more, and the app starts fresh. The checks that every file is
/// gone and that the fake backend deleted the account are made from outside the app (the 24c
/// checkpoint in the plan's progress log); the backend's own tests cover the server side.
final class AccountDeletionTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testDeleteMyAccountStartsTheAppFresh() {
        let app = XCUIApplication()
        app.launchArguments =
            UITestLaunch.toursOff + UITestLaunch.animationsOff + [
                "-seed-photo-closet", "3", "-fake-signed-in",
            ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: 120), "Home didn't open")

        let drawer = app.buttons["home.privacyDrawer"]
        app.reveal(drawer, timeout: Self.wait)
        drawer.tapUntil(app.navigationBars["Privacy and terms"], appears: Self.wait)
        let row = element("privacy.deleteAccount", in: app)
        app.reveal(row, timeout: Self.wait)
        row.tapUntil(app.navigationBars["Delete my account"], appears: Self.wait)
        XCTAssertTrue(labelled("doesn’t cancel a subscription", in: app).waitUntilExists(timeout: Self.wait))

        // Cancel first: nothing changes.
        let alert = app.alerts["Delete your account?"]
        let delete = element("deleteData.delete", in: app)
        app.reveal(delete, timeout: Self.wait)
        delete.tapUntil(alert, appears: Self.wait)
        alert.buttons["Cancel"].tapUntilGone(timeout: Self.wait)
        XCTAssertTrue(app.navigationBars["Delete my account"].exists)

        delete.tapUntil(alert, appears: Self.wait)
        alert.buttons["Delete my account"].tapUntilGone(timeout: Self.wait)

        // The fake Apple sheet answers at once; the fake backend finishes at once; the app starts
        // fresh on the welcome.
        XCTAssertTrue(
            app.buttons["welcome.getStarted"].waitUntilExists(timeout: Self.wait), "Didn't go back to the welcome")
        XCTAssertTrue(labelled("Your data is deleted", in: app).waitUntilExists(timeout: Self.wait))
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func labelled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
}
