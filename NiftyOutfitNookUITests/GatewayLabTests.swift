import XCTest

/// The debug gateway screen (`-gateway-lab`, Phase 24a): the fake Apple sign-in, an
/// authenticated call through the in-process fake backend, and how an expired token, no
/// connection and a 429 look to her. Screenshots are kept as the checkpoint's evidence.
final class GatewayLabTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSignInAndTheFailureModes() {
        let app = XCUIApplication()
        app.launchArguments = ["-gateway-lab"] + UITestLaunch.animationsOff
        app.launch()
        XCTAssertTrue(app.navigationBars["Gateway"].waitUntilExists(timeout: uiTestWait))

        let status = app.staticTexts["gatewayLab.status"]
        let message = app.staticTexts["gatewayLab.message"]
        XCTAssertTrue(status.waitUntilLabel(contains: "Signed out", timeout: uiTestWait))

        // Sign in with the fake Apple sign-in, then the authenticated who-am-I call.
        app.buttons["gatewayLab.signIn"].tap()  // tap-unconfirmed: the next line waits for the status
        XCTAssertTrue(status.waitUntilLabel(contains: "Signed in as usr_", timeout: uiTestWait))
        whoAmI(app)
        XCTAssertTrue(message.waitUntilLabel(contains: "The backend says you're usr_", timeout: uiTestWait))
        keepScreenshot("1-signed-in-who-am-i")

        // The token expires on the way: one 401, a fresh token, and the call still works.
        choose("expiredToken", in: app)
        whoAmI(app)
        XCTAssertTrue(message.waitUntilLabel(contains: "The backend says you're usr_", timeout: uiTestWait))
        let lastCall = app.descendants(matching: .any)["gatewayLab.lastCall"]
        XCTAssertTrue(lastCall.waitUntilLabel(contains: "← me 401 token_expired", timeout: uiTestWait))
        XCTAssertTrue(lastCall.label.contains("fresh token, trying once more"))
        XCTAssertTrue(lastCall.label.contains("← me 200"))
        keepScreenshot("2-expired-token-refreshed", showing: message)

        // No connection.
        choose("offline", in: app)
        whoAmI(app)
        XCTAssertTrue(message.waitUntilLabel(contains: "You're offline.", timeout: uiTestWait))
        keepScreenshot("3-offline", showing: message)

        // 429 with a long Retry-After: said plainly, and Who am I? waits.
        choose("rateLimited", in: app)
        whoAmI(app)
        XCTAssertTrue(message.waitUntilLabel(contains: "Too many tries. Try again in 30 seconds.", timeout: uiTestWait))
        XCTAssertFalse(app.buttons["gatewayLab.whoAmI"].isEnabled)
        keepScreenshot("4-rate-limited", showing: message)

        // Signing out ends it.
        app.buttons["gatewayLab.signOut"].tap()  // tap-unconfirmed: the next line waits for the status
        XCTAssertTrue(status.waitUntilLabel(contains: "Signed out", timeout: uiTestWait))
    }

    /// Phase 26: with no connection (`-connection offline` fixes the state), a calm banner says so
    /// and what still works; and a connection that drops in the middle of a call is tried again
    /// without her doing anything.
    @MainActor
    func testTheOfflineBannerAndAConnectionLostInTheMiddle() {
        let app = XCUIApplication()
        app.launchArguments = ["-gateway-lab", "-connection", "offline"] + UITestLaunch.animationsOff
        app.launch()
        XCTAssertTrue(app.navigationBars["Gateway"].waitUntilExists(timeout: uiTestWait))
        let banner = app.staticTexts["cloudOfflineBanner"]
        XCTAssertTrue(banner.waitUntilExists(timeout: uiTestWait))
        XCTAssertTrue(banner.label.contains("offline."))
        XCTAssertTrue(banner.label.contains("Your closet still works on this iPhone."))
        keepScreenshot("5-offline-banner")

        // The state is a hint only: with the fake backend reachable, a call still goes through, and
        // when the connection drops in the middle of it, it is tried again.
        let status = app.staticTexts["gatewayLab.status"]
        let message = app.staticTexts["gatewayLab.message"]
        app.buttons["gatewayLab.signIn"].tap()  // tap-unconfirmed: the next line waits for the status
        XCTAssertTrue(status.waitUntilLabel(contains: "Signed in as usr_", timeout: uiTestWait))
        choose("connectionLost", in: app)
        whoAmI(app)
        XCTAssertTrue(message.waitUntilLabel(contains: "The backend says you're usr_", timeout: uiTestWait))
        let lastCall = app.descendants(matching: .any)["gatewayLab.lastCall"]
        XCTAssertTrue(lastCall.waitUntilLabel(contains: "connection lost, retrying", timeout: uiTestWait))
        XCTAssertTrue(lastCall.label.contains("← me 200"))
        keepScreenshot("6-connection-lost-then-retried", showing: message)
    }

    @MainActor
    private func choose(_ mode: String, in app: XCUIApplication) {
        // The list builds rows as they scroll in, so a mode further down may not exist yet.
        let button = app.buttons["gatewayLab.mode.\(mode)"]
        for _ in 0..<8 where !(button.exists && button.isHittable) {
            app.dragPage(up: true)
        }
        XCTAssertTrue(button.isHittable, "Can't reach the \(mode) mode")
        button.tapUntilSelected(timeout: uiTestWait)
    }

    @MainActor
    private func whoAmI(_ app: XCUIApplication) {
        let button = app.buttons["gatewayLab.whoAmI"]
        for _ in 0..<8 where !(button.exists && button.isHittable) {
            app.dragPage(up: false)
        }
        XCTAssertTrue(button.isHittable, "Can't reach Who am I?")
        button.tap()  // tap-unconfirmed: each caller waits for the call's result message next
    }

    @MainActor
    private func keepScreenshot(_ name: String, showing element: XCUIElement? = nil) {
        if let element {
            for _ in 0..<6 where !(element.exists && element.isHittable) {
                XCUIApplication().dragPage(up: false)
            }
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
