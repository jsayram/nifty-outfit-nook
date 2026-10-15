import XCTest

// Waits that end on the app's state, shared by the UI tests. None of them sleeps: each one ends
// as soon as its condition holds, and fails with a message when it doesn't within the timeout.
//
// They exist because the hosted CI runner is slow and uneven (one query can take seconds), and a
// tap that lands while a screen is still moving can be lost. Two of those flaked on CI: a tap on
// Home right after Back, while the pushed screen was still sliding away, and Not now on the
// laundry sheet at AX5 after the test had swiped the sheet itself.

extension XCUIElement {
    /// Waits until the element exists and can be tapped.
    @MainActor
    func waitUntilHittable(timeout: TimeInterval) -> Bool {
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: self)
        return XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed
    }

    /// Taps the element once it can be tapped.
    @MainActor
    func tapWhenHittable(timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntilHittable(timeout: timeout), "Can't tap \(self)", file: file, line: line)
        tap()
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
            if waitForNonExistence(timeout: timeout) { return }
        }
        XCTAssertFalse(exists, "\(self) is still there after tapping it", file: file, line: line)
    }

    /// Taps a tab or other selectable button and waits until it says it's selected, tapping once
    /// more if the first tap was lost while the screen was still changing.
    @MainActor
    func tapUntilSelected(timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        let selected = NSPredicate(format: "selected == true")
        for _ in 0..<2 {
            guard waitUntilHittable(timeout: timeout) else { break }
            tap()
            let expectation = XCTNSPredicateExpectation(predicate: selected, object: self)
            if XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed { return }
        }
        XCTAssertTrue(isSelected, "\(self) didn't become selected", file: file, line: line)
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
        bar.buttons.firstMatch.tapWhenHittable(timeout: timeout, file: file, line: line)
        XCTAssertTrue(bar.waitForNonExistence(timeout: timeout), "\(title) didn't close", file: file, line: line)
        XCTAssertTrue(
            navigationBars[destination].waitUntilHittable(timeout: timeout), "No way back from \(title)", file: file,
            line: line)
    }
}
