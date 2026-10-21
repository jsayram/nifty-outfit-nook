import XCTest

/// Phase 29, live weather, with the stand-ins for Apple's parts (`-weather-cities fixture`,
/// `-weather-location askDeny`): pick a city with no permission, see the window and Apple's
/// credit on Home, turn on "Use my location" and say no, and check the fallback to the city.
/// Screenshots are kept as the checkpoint's evidence (`NOOK_SCREENSHOT_DIR`).
final class WeatherTests: XCTestCase {
    static let wait = uiTestWait

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(weather: String = "snow", location: String = "askDeny") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            UITestLaunch.standard + [
                "-fixtures", "demo:weather=\(weather)", "-weather-cities", "fixture", "-weather-location", location,
                "-weather-settings-memory",
            ]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Taps a switch until its value changes, as Settings' tests do.
    @MainActor
    private func flip(_ toggle: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let before = toggle.value as? String
        let flipped: @MainActor () -> Bool = { toggle.exists && (toggle.value as? String) != before }
        let inner = toggle.switches.firstMatch
        let didFlip =
            inner.exists
            ? inner.tapUntil(timeout: Self.wait, flipped)
            : toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tapUntil(timeout: Self.wait, flipped)
        XCTAssertTrue(didFlip, "\(toggle) didn't flip", file: file, line: line)
    }

    /// Taps the location switch until the explanation shows. The switch itself stays off until she
    /// has answered, so its value can't be what's waited on.
    @MainActor
    private func flipToAskLocation(_ toggle: XCUIElement) {
        let explainer = XCUIApplication().alerts["Use the weather where you are?"]
        let inner = toggle.switches.firstMatch
        let target =
            inner.exists ? inner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            : toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        XCTAssertTrue(target.tapUntil(timeout: Self.wait) { explainer.exists }, "The explanation didn't show")
    }

    @MainActor
    private func openPrivacy(_ app: XCUIApplication) {
        let drawer = app.buttons["home.privacyDrawer"]
        XCTAssertTrue(drawer.waitUntilExists(timeout: Self.wait))
        drawer.tapUntil(app.navigationBars["Privacy and terms"], appears: Self.wait)
        let found = element("privacy.weather.live", in: app).waitUntilExists(timeout: Self.wait)
        let ids = app.descendants(matching: .any).allElementsBoundByIndex.map(\.identifier).filter { !$0.isEmpty }
        XCTAssertTrue(found, "No Live weather switch. Identifiers: \(ids)")
    }

    @MainActor
    private func turnOnLiveWeather(_ app: XCUIApplication) {
        let live = app.switches["privacy.weather.live"]
        app.scrollUntilHittable(live, up: 6)
        flip(live)
        XCTAssertTrue(element("privacy.weather.city", in: app).waitUntilExists(timeout: Self.wait))
    }

    @MainActor
    private func chooseSeattle(_ app: XCUIApplication) {
        let city = app.buttons["privacy.weather.city"]
        app.scrollUntilHittable(city, up: 6)
        city.tapUntil(element("field.weather.cityField", in: app), appears: Self.wait)
        let field = app.textFields.firstMatch
        field.tap()  // tap-unconfirmed: typing waits for the keyboard
        field.typeText("sea")
        let result = app.buttons["weather.city.Seattle, WA"]
        XCTAssertTrue(result.waitUntilExists(timeout: Self.wait))
        result.tap()  // tap-unconfirmed: the sheet closing is awaited next
        XCTAssertTrue(element("field.weather.cityField", in: app).waitUntilGone(timeout: Self.wait))
    }

    @MainActor
    func testPickACityThenHomeShowsTheWeatherAndTheCredit() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["Window: Snow"].waitUntilExists(timeout: Self.wait))
        // The sample weather is on while Live weather is off: no credit for made-up weather.
        XCTAssertFalse(element("weather.credit", in: app).exists)

        openPrivacy(app)
        turnOnLiveWeather(app)
        // On, but with no city or location yet: it says what's missing.
        XCTAssertTrue(element("privacy.weather.needsPlace", in: app).exists)
        chooseSeattle(app)
        XCTAssertTrue(app.staticTexts["Seattle, WA"].waitUntilExists(timeout: Self.wait))
        XCTAssertFalse(element("privacy.weather.needsPlace", in: app).exists)
        Screenshots.save(app, as: "weather-privacy-city")

        app.goBack(from: "Privacy and terms", to: "Home", timeout: Self.wait)
        XCTAssertTrue(app.descendants(matching: .any)["Window: Snow"].waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(element("weather.credit", in: app).waitUntilExists(timeout: Self.wait))
        Screenshots.save(app, as: "weather-home-snow-credit")
    }

    @MainActor
    func testDenyingLocationFallsBackToTheCity() {
        let app = launch(weather: "rain")
        openPrivacy(app)
        turnOnLiveWeather(app)
        chooseSeattle(app)

        let location = app.switches["privacy.weather.location"]
        app.scrollUntilHittable(location, up: 6)
        flipToAskLocation(location)
        let explainer = app.alerts["Use the weather where you are?"]
        XCTAssertTrue(explainer.waitUntilExists(timeout: Self.wait))
        Screenshots.save(app, as: "weather-location-explainer")
        explainer.buttons["Continue"].firstMatch.tap()  // tap-unconfirmed: the blocked note appears next

        // iOS said no: the switch is back off, Settings is offered, the city stays.
        XCTAssertTrue(element("privacy.weather.blocked", in: app).waitUntilExists(timeout: Self.wait))
        XCTAssertTrue(element("privacy.weather.openSettings", in: app).exists)
        XCTAssertEqual(app.switches["privacy.weather.location"].value as? String, "0")
        XCTAssertTrue(app.staticTexts["Seattle, WA"].exists)
        Screenshots.save(app, as: "weather-location-denied")

        // Home still has the weather, from the city.
        app.goBack(from: "Privacy and terms", to: "Home", timeout: Self.wait)
        XCTAssertTrue(app.descendants(matching: .any)["Window: Rain"].waitUntilExists(timeout: Self.wait))
    }

    @MainActor
    func testAllowingLocationNeedsNoCity() {
        let app = launch(weather: "sun", location: "ask")
        openPrivacy(app)
        turnOnLiveWeather(app)
        let location = app.switches["privacy.weather.location"]
        app.scrollUntilHittable(location, up: 6)
        flipToAskLocation(location)
        let explainer = app.alerts["Use the weather where you are?"]
        XCTAssertTrue(explainer.waitUntilExists(timeout: Self.wait))
        explainer.buttons["Continue"].firstMatch.tap()  // tap-unconfirmed: the note about a place goes next
        XCTAssertTrue(element("privacy.weather.needsPlace", in: app).waitUntilGone(timeout: Self.wait))
        XCTAssertEqual(app.switches["privacy.weather.location"].value as? String, "1")
        XCTAssertFalse(element("privacy.weather.blocked", in: app).exists)
    }

    @MainActor
    func testTypeACityInsteadFromTheExplanation() {
        let app = launch(location: "askDeny")
        openPrivacy(app)
        turnOnLiveWeather(app)
        let location = app.switches["privacy.weather.location"]
        app.scrollUntilHittable(location, up: 6)
        flipToAskLocation(location)
        let explainer = app.alerts["Use the weather where you are?"]
        XCTAssertTrue(explainer.waitUntilExists(timeout: Self.wait))
        explainer.buttons["Type a city instead"].firstMatch.tap()  // tap-unconfirmed: the city field appears next
        XCTAssertTrue(element("field.weather.cityField", in: app).waitUntilExists(timeout: Self.wait))
        // No permission was asked: nothing says it was refused.
        XCTAssertEqual(app.switches["privacy.weather.location"].value as? String, "0")
    }

    @MainActor
    func testEveryWindowFollowsTheWeather() {
        for (state, label) in [("sun", "Window: Sunny"), ("cloudy", "Window: Cloudy"), ("night", "Window: Night")] {
            let app = launch(weather: state)
            XCTAssertTrue(
                app.descendants(matching: .any)[label].waitUntilExists(timeout: Self.wait), "\(state) shows no \(label)")
            app.terminate()
        }
    }
}
