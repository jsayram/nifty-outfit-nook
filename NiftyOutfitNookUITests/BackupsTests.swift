import XCTest

/// Backups (Phase 21b), on her own closet in the store: Profile opens Backups, Export a copy
/// shows a generated passphrase, and Export hands the file to the system's Files sheet. Choosing
/// where to save it, and restoring, go through the system's Files screens, which the Phase 21b
/// checkpoint drove by hand on the iPhone 12 simulator.
final class BackupsTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testExportReachesTheFilesSheet() {
        let app = XCUIApplication()
        app.launchArguments =
            ["-onboarding", "reset", "-tour", "off", "-fixtures", "demo"] + UITestLaunch.animationsOff
        app.launch()
        app.buttons["welcome.getStarted"].tapUntil(app.navigationBars["Your name"], appears: Self.wait)
        app.buttons["onboarding.skip"].tapUntil(app.navigationBars["Your closet stays here"], appears: Self.wait)
        app.buttons["onboarding.continue"].tapUntil(
            app.navigationBars["How you like clothes to fit"], appears: Self.wait)
        app.buttons["onboarding.skip"].tapUntil(app.navigationBars["Choose a starting closet"], appears: Self.wait)
        element("onboarding.closet.empty", in: app).tapUntilSelected(timeout: Self.wait)
        app.buttons["onboarding.continue"].tapUntil(app.navigationBars["Home"], appears: Self.wait)

        app.buttons["home.profile"].tapUntil(app.navigationBars["Profile"], appears: Self.wait)
        let backups = app.buttons["profile.backups"]
        XCTAssertTrue(backups.waitUntilExists(timeout: Self.wait), "Backups isn't on Profile")
        app.scrollUntilHittable(backups, up: 12)
        backups.tapUntil(app.buttons["backups.export"], appears: Self.wait)

        app.buttons["backups.export"].tapUntil(element("backups.passphrase", in: app), appears: Self.wait)
        let passphrase = element("backups.passphrase", in: app).label
        XCTAssertEqual(passphrase.count, 29, "A generated passphrase is six groups of four")

        // The encrypted file is written, and the system's Files sheet opens to save it.
        app.buttons["backups.exportButton"].tapUntil(app.buttons["Save"], appears: Self.wait)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
