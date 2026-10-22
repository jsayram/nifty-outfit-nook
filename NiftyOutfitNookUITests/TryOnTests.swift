import XCTest

/// Phase 33a's checkpoint on the simulator: a real try-on picture made from her own closet,
/// against the fake backend's slow image service (`-cloud-tryon slow`, about 15 seconds) and the
/// drawn stand-in photo (`-seed-tryon`; simulators can't run Apple Vision's person and face
/// checks, so `SyntheticPersonAnalyzer` reads the drawing). She starts a try-on, browses the
/// closet, gets the banner, opens the picture, and opens "See what was sent", which shows the
/// faceless photo on the studio backdrop. The rules behind it are the package tests
/// (`HeadMaskingTests`, `HeadRestoreTests`, `PhoneTryOnTests`, `TryOnJobsTests`,
/// `RealTryOnModelTests`, `TryOnGatewayTests`).
final class TryOnTests: XCTestCase {
    static let wait = uiTestWait
    /// The slow image service, with room for a busy simulator.
    static let jobWait: TimeInterval = 60

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testATryOnRunsWhileSheBrowsesAndShowsWhatWasSent() throws {
        try skipOnPullRequests("A seeded closet and a 15-second job; the package tests cover each step.")
        let app = XCUIApplication()
        app.launchArguments =
            UITestLaunch.toursOff + UITestLaunch.animationsOff + [
                "-seed-tryon", "-cloud-tryon", "slow", "-subscription", "active",
            ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: 120), "Home didn't open")

        // The seeded look, from its frame on Home's shelf.
        let frame = app.buttons.matching(NSPredicate(format: "label == %@", "Saved look: Sweater and trousers"))
            .firstMatch
        tap(frame, until: { app.buttons["lookDetail.tryOn"].exists })
        tap(app.buttons["lookDetail.tryOn"], until: { app.buttons["tryOn.make"].exists })
        tap(
            app.buttons["tryOn.make"],
            until: {
                app.buttons["tryOnConsent.allow"].exists || app.buttons["tryOn.leave"].exists
            })
        let allow = app.buttons["tryOnConsent.allow"]
        if allow.exists {
            XCTAssertTrue(app.staticTexts["tryOnConsent.disclosure"].label.contains("Black Forest Labs"))
            tap(allow, until: { app.buttons["tryOn.leave"].exists })
        }
        XCTAssertTrue(app.buttons["tryOn.leave"].waitUntilExists(timeout: Self.wait))
        keepScreenshot("33a-1-dressing-you-can-leave")

        // She leaves and browses her closet while the picture is made.
        tap(app.buttons["tryOn.leave"], until: { !app.buttons["tryOn.leave"].exists })
        tap(app.tabBars.buttons["Closet"], until: { app.searchFields["Search your closet"].exists })

        let banner = app.buttons["jobs.banner"]
        XCTAssertTrue(banner.waitUntilExists(timeout: Self.jobWait), "No banner")
        XCTAssertEqual(banner.label, "Your try-on picture is ready, Tap to see it.")
        XCTAssertTrue(banner.waitUntilHittable(timeout: Self.wait))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 2)
        keepScreenshot("33a-2-banner-over-closet")

        // The banner opens the picture; it isn't labelled Simulated.
        tap(banner, until: { app.buttons["picture.seeWhatWasSent"].exists })
        XCTAssertEqual(app.staticTexts["picture.facts"].label, "Made today")
        keepScreenshot("33a-3-picture")

        tap(
            app.buttons["picture.seeWhatWasSent"],
            until: { app.otherElements["sent.person"].exists || app.images["sent.person"].exists })
        XCTAssertTrue(app.staticTexts["sent.line"].label.contains("Your face never leaves your phone"))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "images")], timeout: 2)
        keepScreenshot("33a-4-see-what-was-sent")
    }

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
    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
