import UserNotifications
import XCTest

/// Background AI jobs (Phase 27c) on the real screens, against the fake backend's slow stylist
/// (`-cloud-stylist slow`, about 15 seconds an answer): she starts Style Me, browses and searches
/// the closet while it works, the banner says her looks are ready, and tapping it shows them. In
/// the background, a local notification says so instead. The rules behind each are `AIJobsTests`
/// (relaunch, same key, one at a time, Cancel) and `YourLooksCloudTests` in the package, and the
/// "no second charge" checks in `AIJobsResumeTests` and the backend's own tests.
final class BackgroundJobsTests: XCTestCase {
    static let wait = uiTestWait
    /// The slow stylist's answer, with room for a busy simulator.
    static let jobWait: TimeInterval = 60

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testSheSearchesTheClosetWhileItStylesThenTheBannerOpensHerLooks() {
        let app = launch()
        startStyleMe(in: app)
        XCTAssertTrue(app.staticTexts["results.leavingNote"].label.hasPrefix("You can leave this screen"))
        // The offer shows only until iOS has an answer or she says Not now, on this simulator.
        let notNow = app.buttons["results.notifyNotNow"]
        if notNow.waitUntilExists(timeout: 3) {
            tap(notNow, until: { !notNow.exists })
        }
        keepScreenshot("27c-1-styling-can-leave")

        // Off to the closet to search while the stylist works.
        tap(app.tabBars.buttons["Closet"], until: { app.searchFields["Search your closet"].exists })
        let search = app.searchFields["Search your closet"]
        search.tapUntilFocused(timeout: Self.wait)
        search.typeTextAndWait("top\n", timeout: Self.wait)
        keepScreenshot("27c-2-searching-the-closet")

        // The banner when it's done, over the closet; tapping it opens her looks.
        let banner = app.buttons["jobs.banner"]
        XCTAssertTrue(banner.waitUntilExists(timeout: Self.jobWait), "No banner")
        XCTAssertEqual(banner.label, "Your looks are ready, Tap to see them.")
        XCTAssertTrue(banner.waitUntilHittable(timeout: Self.wait))
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 3)
        keepScreenshot("27c-3-banner-over-closet")
        tap(banner, until: { app.buttons["results.version.simple"].exists })
        XCTAssertTrue(app.navigationBars["Your looks"].exists)
        XCTAssertFalse(banner.exists)
        keepScreenshot("27c-4-looks-from-banner")
    }

    @MainActor
    func testInTheBackgroundANotificationSaysTheyAreReady() throws {
        try skipOnPullRequests(
            "iOS's own alert and the Home Screen are slow to script on CI; AIJobsTests covers the notification.")
        let app = launch()
        startStyleMe(in: app)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // On a simulator that already answered, the offer doesn't show again.
        let notifyMe = app.buttons["results.notifyMe"]
        if notifyMe.waitUntilExists(timeout: 3) {
            tap(notifyMe, until: { springboard.alerts.firstMatch.exists })
            keepScreenshot("27c-5-ios-asks")
            let allow = springboard.alerts.buttons["Allow"]
            allow.tapUntil(timeout: Self.wait, else: "iOS's alert stayed") { !springboard.alerts.firstMatch.exists }
        }

        // She leaves the app mid-job.
        XCUIDevice.shared.press(.home)
        let note = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Your outfit ideas are ready")).firstMatch
        let showed = note.waitUntilExists(timeout: Self.jobWait)
        // A simulator whose notification service doesn't answer can't show anything (see
        // `notificationServiceAnswers`): that is the simulator, not the app, so skip with the
        // reason. With a working service a missing notification still fails.
        if !showed {
            try XCTSkipUnless(
                Self.notificationServiceAnswers(),
                "This simulator's notification service doesn't answer, so no notification can show. Seen on "
                    + "the iOS 27.0 simulator under heavy host load: SpringBoard's notification server waits on a "
                    + "deadlocked dasd (October 2026). A simulator on iOS 26.5 works (NOOK_SIM_OS=26.5).")
        }
        XCTAssertTrue(showed, "No notification")
        XCTAssertFalse(note.label.contains("blouse") || note.label.contains("trousers"), note.label)
        keepScreenshot("27c-6-notification")
        note.tapUntil(timeout: Self.wait, else: "The notification didn't open her looks") {
            app.buttons["results.version.simple"].exists
        }
        keepScreenshot("27c-7-looks-from-notification")
    }

    /// Her own closet in the store (`-seed-photo-closet`): the app is killed mid-job, and after
    /// the relaunch the kept job is asked again with its key and finishes, with the banner. Here
    /// the fake backend starts afresh with the app, so it runs the job again; "never charged
    /// twice" is the real backend's record (backend `tests/jobs.test.ts`) and `AIJobsResumeTests`.
    @MainActor
    func testAJobKilledMidwayFinishesAfterARelaunch() throws {
        try skipOnPullRequests("Two launches and a seeded closet; AIJobsTests covers the relaunch.")
        let app = XCUIApplication()
        app.launchArguments =
            UITestLaunch.toursOff + UITestLaunch.animationsOff + [
                "-seed-photo-closet", "8", "-cloud-stylist", "slow",
            ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: 120), "Home didn't open")
        tap(app.buttons["home.laptop"], until: { app.navigationBars["Style Me"].exists })
        tap(app.buttons["styleMe.go"], until: { app.navigationBars["Your looks"].exists })
        let allow = app.buttons["stylistConsent.allow"]
        if app.buttons["Review"].waitUntilExists(timeout: 5) {
            tap(app.buttons["Review"], until: { allow.exists })
            tap(allow, until: { app.staticTexts["results.styling"].exists })
        }
        // Her own closet and history are kept on the simulator between runs (a CI retry, a second
        // local run). The same request again comes from her history, so ask afresh with New ideas.
        let styling = app.staticTexts["results.styling"]
        if !styling.waitUntilExists(timeout: 5), app.buttons["results.tryDifferent"].exists {
            tap(app.buttons["results.tryDifferent"], until: { styling.exists })
        }
        XCTAssertTrue(styling.waitUntilExists(timeout: Self.wait))
        keepScreenshot("27c-8-styling-before-kill")

        // Killed mid-job, then opened again.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: 120), "Home didn't open again")
        let banner = app.buttons["jobs.banner"]
        XCTAssertTrue(banner.waitUntilExists(timeout: Self.jobWait), "No banner after the relaunch")
        XCTAssertTrue(banner.label.hasPrefix("Your looks are ready"), banner.label)
        XCTAssertTrue(banner.waitUntilHittable(timeout: Self.wait))
        keepScreenshot("27c-9-banner-after-relaunch")
        tap(banner, until: { app.buttons["results.version.simple"].exists })
        keepScreenshot("27c-10-looks-after-relaunch")
    }

    // MARK: Helpers

    /// Whether iOS answers a question about notifications within 20 seconds. The same service
    /// answers the app's own, and posts what it posts. Asked only after no notification showed.
    private static func notificationServiceAnswers() -> Bool {
        let answered = XCTestExpectation(description: "notification settings")
        answered.assertForOverFulfill = false
        UNUserNotificationCenter.current().getNotificationSettings { _ in answered.fulfill() }
        return XCTWaiter().wait(for: [answered], timeout: 20) == .completed
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = UITestLaunch.standard + ["-fixtures", "demo", "-cloud-stylist", "slow"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitUntilExists(timeout: Self.wait))
        return app
    }

    /// From the Home laptop, Style me with the defaults, then her OK to the stylist.
    @MainActor
    private func startStyleMe(in app: XCUIApplication) {
        tap(app.buttons["home.laptop"], until: { app.navigationBars["Style Me"].exists })
        tap(app.buttons["styleMe.go"], until: { app.navigationBars["Your looks"].exists })
        tap(app.buttons["Review"], until: { app.buttons["stylistConsent.allow"].exists })
        tap(app.buttons["stylistConsent.allow"], until: { app.staticTexts["results.styling"].exists })
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
