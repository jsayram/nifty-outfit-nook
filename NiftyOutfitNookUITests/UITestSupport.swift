import XCTest

// Waits that end on the app's state, shared by the UI tests. None of them sleeps: each one ends
// as soon as its condition holds, and fails with a message when it doesn't within the timeout.
//
// They exist because the hosted CI runner is slow and uneven (one query can take seconds), and a
// tap that lands while a screen is still moving can be lost. Several of those flaked on CI: a tap
// on Home right after Back, while the pushed screen was still sliding away; Not now on the
// laundry sheet at AX5 after the test had swiped the sheet itself; Delete my data's
// button and Home's hamper at AX5 (October 2026). So a tap on anything that moves the app on
// (pushes, sheets, alerts, tabs) confirms its effect with `tapUntil`, `tapUntilGone` or
// `tapUntilSelected` instead of a bare `tap()`.
//
// Every tap in the UI tests says what it should do, so a lost tap is tapped again and a tap that
// did nothing fails where it happened, not a few lines later. The retry is only taken when the
// effect didn't come, so a toggle, Save or Undo isn't done twice. `scripts/check-ui-taps.sh`
// (run by `scripts/format.sh` and CI) fails on a bare `tap()` outside this file. A tap with no
// effect to wait for (one that checks nothing happens) keeps a bare `tap()` with
// `// tap-unconfirmed: <why>` on the same line.
//
// Use these instead of `waitForExistence(timeout:)`, `waitForNonExistence(timeout:)` and
// `XCTNSPredicateExpectation`. Those look the first time a second after they start, even when
// the condition already holds, and then once a second; with about a thousand waits in the UI
// tests that was around a quarter of their time on CI (October 2026). These look at once, then
// every quarter of a second.

/// How long a UI test waits for something before it fails. A wait ends as soon as its condition
/// holds, so this only matters when something is wrong or the runner stalls. On CI one query took
/// from 9 to 55 seconds while the simulator was busy (October 2026), and with 15 seconds tests
/// failed there and passed on their retry.
let uiTestWait: TimeInterval = 30

/// How often a wait looks again. On CI one look can itself take most of a second.
private let pollInterval: TimeInterval = 0.25

/// Waits until `condition` holds, looking at once and then every `pollInterval`, while the
/// run loop runs (so the app and XCTest keep going). Returns whether it held in time.
@MainActor
func waitUntilTrue(timeout: TimeInterval, _ condition: @escaping @MainActor () -> Bool) -> Bool {
    if condition() { return true }
    let met = XCTestExpectation(description: "condition met")
    // The timer can fire again before the wait returns; a second fulfil is ignored.
    met.assertForOverFulfill = false
    let timer = Timer(timeInterval: pollInterval, repeats: true) { _ in
        MainActor.assumeIsolated {
            if condition() { met.fulfill() }
        }
    }
    RunLoop.current.add(timer, forMode: .default)
    defer { timer.invalidate() }
    return XCTWaiter().wait(for: [met], timeout: timeout) == .completed
}

extension XCUIElement {
    /// Waits until the element exists.
    @MainActor
    @discardableResult
    func waitUntilExists(timeout: TimeInterval) -> Bool {
        waitUntilTrue(timeout: timeout) { self.exists }
    }

    /// Waits until the element doesn't exist.
    @MainActor
    @discardableResult
    func waitUntilGone(timeout: TimeInterval) -> Bool {
        waitUntilTrue(timeout: timeout) { !self.exists }
    }

    /// Waits until the element exists and matches `predicate` (for example
    /// `label CONTAINS "Saved"`, `value == "1"` or `selected == true`).
    @MainActor
    func waitUntil(_ predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        waitUntilTrue(timeout: timeout) { self.exists && predicate.evaluate(with: self) }
    }

    /// Waits until the element's label contains `text`.
    @MainActor
    func waitUntilLabel(contains text: String, timeout: TimeInterval) -> Bool {
        waitUntil(NSPredicate(format: "label CONTAINS %@", text), timeout: timeout)
    }

    /// Waits until the element exists and can be tapped.
    @MainActor
    func waitUntilHittable(timeout: TimeInterval) -> Bool {
        waitUntilTrue(timeout: timeout) { self.exists && self.isHittable }
    }

    /// Taps a button that closes what it's on (a sheet's Not now or Close) and waits for it to
    /// go. If the first tap was lost because the sheet was still settling, the button is still
    /// there and can be tapped, so it's tapped once more. A button that stays after two taps
    /// fails the test.
    @MainActor
    func tapUntilGone(timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<2 {
            guard waitUntilHittable(timeout: timeout) else { break }
            tap()
            if waitUntilGone(timeout: timeout) { return }
        }
        XCTAssertFalse(exists, "\(self) is still there after tapping it", file: file, line: line)
    }

    /// Taps a button that moves on to another screen, like an onboarding step's Continue, and
    /// waits for `next` (that screen's bar, say) to appear, tapping once more if it didn't and
    /// the button can still be tapped. On CI the runner sometimes loses a tap.
    @MainActor
    func tapUntil(
        _ next: XCUIElement, appears timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line
    ) {
        let appeared = tapUntil(timeout: timeout) { next.exists }
        XCTAssertTrue(appeared, "\(next) didn't appear after tapping \(self)", file: file, line: line)
    }

    /// Taps the element and waits until `effect` holds (a label changed, a step moved on), tapping
    /// once more if it didn't and the element can still be tapped. Returns whether it held. For
    /// any tap whose effect isn't a new element appearing or this one going.
    @MainActor
    @discardableResult
    func tapUntil(timeout: TimeInterval, _ effect: @escaping @MainActor () -> Bool) -> Bool {
        for _ in 0..<2 {
            // Wait a moment for it to settle. A few elements never say they're hittable but take
            // a tap anyway (a Closet piece after a search, Closet's Recently deleted tile), so
            // after that one that exists is tapped.
            guard waitUntilHittable(timeout: min(timeout, 5)) || exists else { break }
            tap()
            if waitUntilTrue(timeout: timeout, effect) { return true }
        }
        return effect()
    }

    /// `tapUntil(timeout:_:)` that fails the test with `message` when the effect doesn't come.
    @MainActor
    func tapUntil(
        timeout: TimeInterval, else message: @autoclosure () -> String, file: StaticString = #filePath,
        line: UInt = #line, _ effect: @escaping @MainActor () -> Bool
    ) {
        XCTAssertTrue(tapUntil(timeout: timeout, effect), message(), file: file, line: line)
    }

    /// Types `text` into a field that has the keyboard (see `tapUntilFocused`) and waits until the
    /// field's value contains `expected`, which is the text without a final Return unless given.
    /// The text is never typed again: a second go would type it twice. A field that didn't get
    /// it fails the test here rather than at a later check.
    @MainActor
    func typeTextAndWait(
        _ text: String, expecting expected: String? = nil, timeout: TimeInterval, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        typeText(text)
        let wanted = expected ?? (text.hasSuffix("\n") ? String(text.dropLast()) : text)
        let landed = waitUntilTrue(timeout: timeout) {
            self.exists && (self.value as? String)?.contains(wanted) == true
        }
        XCTAssertTrue(landed, "\(self) doesn't show \"\(wanted)\"", file: file, line: line)
    }

    /// Taps a tab or other selectable button and waits until it says it's selected, tapping once
    /// more if the first tap was lost while the screen was still changing.
    @MainActor
    func tapUntilSelected(timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<2 {
            guard waitUntilHittable(timeout: timeout) else { break }
            tap()
            if waitUntilSelected(timeout: timeout) { return }
        }
        XCTAssertTrue(isSelected, "\(self) didn't become selected", file: file, line: line)
    }

    /// Waits until the element's frame is the same on two looks in a row, a poll apart: a window
    /// being resized or a page being scrolled has stopped.
    @MainActor
    func waitUntilStill(timeout: TimeInterval) -> Bool {
        let last = FrameBox()
        return waitUntilTrue(timeout: timeout) {
            let now = self.frame
            defer { last.frame = now }
            return now == last.frame
        }
    }

    /// Waits until a tab or other selectable button says it's selected.
    @MainActor
    func waitUntilSelected(timeout: TimeInterval) -> Bool {
        waitUntilTrue(timeout: timeout) { self.exists && self.isSelected }
    }

    /// Whether a text field or search field is there and has the keyboard, looked at once.
    @MainActor
    var hasKeyboardNow: Bool {
        exists && NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: self)
    }

    /// Waits until a text field or search field has the keyboard.
    @MainActor
    func waitUntilFocused(timeout: TimeInterval) -> Bool {
        waitUntil(NSPredicate(format: "hasKeyboardFocus == true"), timeout: timeout)
    }

    /// Taps a text field or search field and waits until it has the keyboard, tapping once more
    /// if the first tap was lost. `typeText` straight after a plain tap failed on CI ("Neither
    /// element nor any descendant has keyboard focus") when the runner took seconds to deliver
    /// the tap, or the tap landed while the sidebar beside the field was still changing.
    @MainActor
    func tapUntilFocused(timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<2 {
            guard waitUntilHittable(timeout: timeout) else { break }
            tap()
            if waitUntilFocused(timeout: timeout) { return }
        }
        XCTFail("\(self) didn't get the keyboard", file: file, line: line)
    }
}

extension XCUICoordinate {
    /// Taps this point and waits until `effect` holds, tapping once more if it didn't. For a spot
    /// with no element of its own to tap: the end of a text field, a switch at the end of its row,
    /// a control XCUITest wrongly calls not hittable. Returns whether the effect held.
    @MainActor
    @discardableResult
    func tapUntil(timeout: TimeInterval, _ effect: @escaping @MainActor () -> Bool) -> Bool {
        for _ in 0..<2 {
            tap()
            if waitUntilTrue(timeout: timeout, effect) { return true }
        }
        return effect()
    }
}

/// The frame `waitUntilStill` saw last. It starts as `.null`, so the first look never matches.
@MainActor
private final class FrameBox {
    var frame = CGRect.null
}

extension XCUIApplication {
    /// Scrolls the page until `element` can be tapped, toward it first, then the other way.
    ///
    /// Each scroll is a drag that holds still before it lets go, so the page stops where the
    /// finger stops. A swipe flings the page, and a tap that lands while it's still gliding only
    /// stops the scroll: on CI that lost taps on Help's Still stuck?, Privacy's Delete my data and
    /// the Track laundry switch right after a swipe.
    @MainActor
    func reveal(
        _ element: XCUIElement, timeout: TimeInterval, drags: Int = 6, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitUntilExists(timeout: timeout), "Missing \(element)", file: file, line: line)
        scrollUntilHittable(element, up: drags, down: drags)
        XCTAssertTrue(element.isHittable, "Can't reach \(element)", file: file, line: line)
    }

    /// Drags the page up to `up` times and down to `down` times, until `element` can be tapped,
    /// without failing if it can't. See `reveal`.
    @MainActor
    func scrollUntilHittable(_ element: XCUIElement, up: Int, down: Int = 0) {
        if element.isHittable { return }
        // Start toward it: down first when it's above the middle of the screen.
        let passes = down > 0 && element.frame.midY < frame.midY ? [false, true] : [true, false]
        for dragsUp in passes {
            // `for ... where` would ask on every pass, even once it's found; each ask is a query.
            for _ in 0..<(dragsUp ? up : down) {
                dragPage(up: dragsUp)
                if element.isHittable { return }
            }
        }
    }

    /// Drags the page by a third of the screen and holds still before letting go, so it doesn't
    /// glide on. `up` shows what's further down. The drag stays in the top half of the screen,
    /// above the keyboard when it's up.
    @MainActor
    func dragPage(up: Bool) {
        let low = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let high = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let (start, end) = up ? (low, high) : (high, low)
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.3)
    }
}

extension XCUIApplication {
    /// Taps Back on the screen titled `title` and waits until that screen has gone and
    /// `destination` is showing. The destination's bar is there while the pushed screen is still
    /// sliding away, so waiting for it alone let the next tap land mid-transition.
    @MainActor
    func goBack(
        from title: String, to destination: String, timeout: TimeInterval, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bar = navigationBars[title]
        let back = bar.buttons.firstMatch
        // A Back tap can be lost the same way, so tap once more only if the screen is still there.
        for _ in 0..<2 {
            guard back.waitUntilHittable(timeout: timeout) else { break }
            back.tap()
            if bar.waitUntilGone(timeout: timeout) { break }
        }
        XCTAssertFalse(bar.exists, "\(title) didn't close after Back", file: file, line: line)
        XCTAssertTrue(
            navigationBars[destination].waitUntilHittable(timeout: timeout), "No way back from \(title)", file: file,
            line: line)
    }
}

/// Launch arguments every UI test shares.
enum UITestLaunch {
    /// Turns "Show tips on new screens" off, so Home's quick tour (Phase 16a) doesn't cover what
    /// a test taps. The tour's own tests (`HomeTourTests`) leave it out.
    static let toursOff = ["-tour", "off"]
    /// Opens Home straight away for this launch, on the `-fixtures` set as it is, writing nothing
    /// (Phase 17). Every UI test passes it except `OnboardingTests`, which is about onboarding.
    ///
    /// Since Phase 17 the onboarding state and the tours seen are kept across launches, also
    /// between tests on one simulator, so each test sets what it relies on with these flags
    /// rather than counting on a fresh install.
    static let skipOnboarding = ["-onboarding", "skip"]
    /// Turns UIKit's animations off for this launch (debug builds only), so pushes, sheets and
    /// alerts appear at once. XCUITest waits for the app to be idle after every action, and on CI
    /// those waits were the biggest share of a test's time; locally it took Home, Saved Looks and
    /// Settings from 283 to 235 seconds (October 2026). Tests about tours, onboarding and the iPad
    /// layouts leave it out, so animated transitions are still exercised.
    static let animationsOff = ["-animations", "off"]
    /// Tours off, onboarding skipped and animations off: what most tests launch with.
    static let standard = toursOff + skipOnboarding + animationsOff
}
