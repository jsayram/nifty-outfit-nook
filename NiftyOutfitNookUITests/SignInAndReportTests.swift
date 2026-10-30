import XCTest

/// Release: Sign in with Apple only when she first uses a cloud feature, Profile's account row,
/// and Report a problem on the stylist's looks, against the in-process fake backend and the fake
/// Sign in with Apple of a debug build. The rules behind them are `SignInGateTests`,
/// `SignInFlowTests` and `AIReportModelTests` in the package, and the backend's own tests.
final class SignInAndReportTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    /// Style Me while signed out: nothing asks at launch; the sheet comes when the cloud stylist
    /// is first needed; Not now gives Quick ideas with Sign in beside them; signing in carries the
    /// request on to the stylist's looks; and Report a problem sends a report.
    @MainActor
    func testStyleMeAsksToSignInCarriesOnAndALookCanBeReported() {
        let app = XCUIApplication()
        app.launchArguments =
            UITestLaunch.standard + ["-fixtures", "demo", "-cloud-stylist", "normal", "-signed-out"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: Self.wait))
        let sheet = Self.element("signIn.sheet", in: app)
        XCTAssertFalse(sheet.exists, "Nothing asks at launch")

        tap(app.buttons["home.laptop"], until: { app.navigationBars["Style Me"].exists })
        tap(app.buttons["styleMe.go"], until: { app.navigationBars["Your looks"].exists })
        // Her OK to the stylist's provider comes first, as before.
        tap(app.buttons["Review"], until: { app.buttons["stylistConsent.allow"].exists })
        tap(app.buttons["stylistConsent.allow"], until: { sheet.exists })
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "signIn.apple").firstMatch.waitUntilExists(
                timeout: Self.wait))
        XCTAssertTrue(Self.element("signIn.privacy", in: app).exists)
        // F1: Sign in with Apple waits for "I'm 18 or older".
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "signIn.apple").firstMatch.isEnabled)
        Screenshots.save(app, as: "1-sign-in-sheet")

        // Not now: Quick ideas, nothing sent, and Sign in beside them.
        tap(app.buttons["signIn.notNow"], until: { !sheet.exists })
        let quickIdeas = Self.element("results.quickIdeas", in: app)
        XCTAssertTrue(quickIdeas.waitUntilExists(timeout: Self.wait))
        let signIn = app.buttons["Sign in"]
        XCTAssertTrue(signIn.waitUntilExists(timeout: Self.wait))

        // Sign in: the stylist's looks, with the why line, without asking again.
        tap(signIn, until: { sheet.exists })
        app.confirmAdultForSignIn()
        tap(app.descendants(matching: .any).matching(identifier: "signIn.apple").firstMatch, until: { !sheet.exists })
        XCTAssertTrue(app.staticTexts["results.why"].waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(quickIdeas.exists)

        // Report a problem: a reason, Send, and a reference back.
        let report = app.buttons["results.report"]
        tap(report, until: { Self.element("report.sheet", in: app).exists })
        tap(
            Self.element("report.reason.notMyClothes", in: app),
            until: {
                Self.element("report.reason.notMyClothes", in: app).isSelected
            })
        XCTAssertTrue(Self.element("report.subject.why", in: app).exists)
        XCTAssertFalse(Self.element("report.includePicture", in: app).exists, "A look has no picture to send")
        Screenshots.save(app, as: "3-report-sheet")
        tap(Self.element("report.send", in: app), until: { Self.element("report.sent", in: app).exists })
        XCTAssertTrue(Self.labelled("Reference NK-", in: app).exists)
        tap(Self.element("report.done", in: app), until: { !Self.element("report.sheet", in: app).exists })
    }

    /// Profile's row: Sign in opens the sheet; once in, it says Signed in with Apple; Sign out asks
    /// first and leaves her closet as it is.
    @MainActor
    func testProfileRowSignsInAndOut() {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo"]
        app.launch()
        app.buttons["home.profile"].tapUntil(app.navigationBars["Profile"], appears: Self.wait)
        let row = app.buttons.matching(identifier: "profile.account").firstMatch
        app.reveal(row, timeout: Self.wait)
        XCTAssertTrue(row.label.hasPrefix("Sign in"), "Profile's row says \(row.label)")

        tap(row, until: { Self.element("signIn.sheet", in: app).exists })
        app.confirmAdultForSignIn()
        tap(
            app.descendants(matching: .any).matching(identifier: "signIn.apple").firstMatch,
            until: { !Self.element("signIn.sheet", in: app).exists })
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Signed in with Apple")).firstMatch
                .waitUntilExists(timeout: Self.wait))
        Screenshots.save(app, as: "2-profile-row")

        tap(row, until: { app.buttons.matching(identifier: "profile.signOut.confirm").firstMatch.exists })
        tap(
            app.buttons.matching(identifier: "profile.signOut.confirm").firstMatch,
            until: { row.label.hasPrefix("Sign in") })
    }

    // MARK: Helpers

    @MainActor
    private func tap(
        _ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line,
        until effect: @escaping @MainActor () -> Bool
    ) {
        XCTAssertTrue(button.waitUntilExists(timeout: Self.wait), "No button \(button)", file: file, line: line)
        XCUIApplication().scrollUntilHittable(button, up: 12, down: 12)
        button.tapUntil(timeout: Self.wait, else: "\(button) didn't do its job", file: file, line: line, effect)
    }

    @MainActor
    private static func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private static func labelled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
}
