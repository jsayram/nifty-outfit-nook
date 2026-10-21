import XCTest

/// The debug limits screen (`-limits-lab`, Phase 24b) on the fake backend: a burst hits the rate
/// limit, the try-on allowance runs out, the kill switch pauses try-on, and a paid action sent
/// again with the same key (or whose first answer was lost) isn't run twice. Screenshots are kept
/// as the checkpoint's evidence.
final class LimitsLabTests: XCTestCase {
    private static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLimitsKillSwitchAndRetries() {
        let app = XCUIApplication()
        app.launchArguments = ["-limits-lab"] + UITestLaunch.animationsOff
        app.launch()
        XCTAssertTrue(app.navigationBars["Limits"].waitUntilExists(timeout: Self.wait))

        let message = app.staticTexts["limitsLab.message"]
        let detail = app.staticTexts["limitsLab.detail"]
        let tryOnMeter = app.descendants(matching: .any)["limitsLab.meter.tryOn"]
        tap("signIn", in: app) { tryOnMeter.exists }

        // A burst: five go through, the sixth is throttled.
        for count in 1...5 {
            tap("askStylist", in: app) { detail.exists && detail.label.contains("Jobs run on the server: \(count) ") }
        }
        tap("askStylist", in: app) { message.label.contains("You've asked a lot in the last minute.") }
        keepScreenshot("1-rate-limited", showing: message, in: app)

        // Try-on pictures: three a day, then the allowance message with when more come back.
        tap("startOver", in: app) { !message.exists }
        for count in 1...3 {
            tap("tryOn", in: app) { detail.exists && detail.label.contains("Jobs run on the server: \(count) ") }
        }
        tap("tryOn", in: app) { message.label.contains("You've used your try-on pictures for now. More ") }
        XCTAssertTrue(
            tryOnMeter.waitUntil(NSPredicate(format: "value CONTAINS %@", "0 of 3 left today"), timeout: Self.wait))
        keepScreenshot("2-allowance-used", showing: message, in: app)

        // The kill switch: try-on paused on the server, the stylist still works.
        tap("startOver", in: app) { !message.exists }
        flip(app.switches["limitsLab.pause.tryOn"], in: app)
        tap("tryOn", in: app) { message.label.contains("Try-on pictures are taking a break.") }
        XCTAssertTrue(
            tryOnMeter.waitUntil(NSPredicate(format: "value CONTAINS %@", "Taking a break"), timeout: Self.wait))
        keepScreenshot("3-kill-switch", showing: message, in: app)
        tap("askStylist", in: app) { message.label.contains("Done: a swap or question") }
        flip(app.switches["limitsLab.pause.tryOn"], in: app)

        // The same key again: answered from the server's record, not run or counted again.
        tap("startOver", in: app) { !message.exists }
        tap("fullOutfit", in: app) {
            detail.exists && detail.label.contains("Run and counted once. Jobs run on the server: 1 (+1)")
        }
        tap("sendAgain", in: app) {
            detail.label.contains("wasn't run or counted again. Jobs run on the server: 1 (+0)")
        }
        keepScreenshot("4-same-key-not-counted-twice", showing: detail, in: app)

        // The first answer is lost on the way back: the app retries with the same key by itself.
        tap("lostAnswer", in: app) {
            detail.label.contains("wasn't run or counted again. Jobs run on the server: 2 (+1)")
        }
        keepScreenshot("5-lost-answer-retried", showing: detail, in: app)
    }

    @MainActor
    private func tap(_ id: String, in app: XCUIApplication, until effect: @escaping @MainActor () -> Bool) {
        let button = app.buttons["limitsLab.\(id)"]
        bringIntoView(button, in: app)
        XCTAssertTrue(button.tapUntil(timeout: Self.wait, effect), "Tapping \(id) didn't do what it should")
    }

    @MainActor
    private func flip(_ toggle: XCUIElement, in app: XCUIApplication) {
        bringIntoView(toggle, in: app)
        let before = toggle.value as? String
        let flipped: @MainActor () -> Bool = { toggle.exists && (toggle.value as? String) != before }
        let inner = toggle.switches.firstMatch
        let didFlip =
            inner.exists
            ? inner.tapUntil(timeout: Self.wait, flipped)
            : toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tapUntil(timeout: Self.wait, flipped)
        XCTAssertTrue(didFlip, "\(toggle) didn't flip")
    }

    /// The list builds rows as they scroll in, so a row further down may not exist yet: drag
    /// toward the end, then back toward the top, until it can be tapped.
    @MainActor
    private func bringIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        for up in [true, false] {
            for _ in 0..<8 where !(element.exists && element.isHittable) {
                app.dragPage(up: up)
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Can't reach \(element)")
    }

    @MainActor
    private func keepScreenshot(_ name: String, showing element: XCUIElement, in app: XCUIApplication) {
        bringIntoView(element, in: app)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
