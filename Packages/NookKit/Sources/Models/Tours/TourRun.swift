import Foundation

/// One tour while it's showing: which step is on screen, and what each button does to it.
///
/// It's only the sequencing. The screen that shows the tour keeps the words and the controls,
/// and the store keeps the outcome once the run ends. A run isn't stored: replay and relaunch
/// always start again from step 1 (PRD §7.8).
public struct TourRun: Hashable, Sendable {
    public let tour: TourID
    public let version: Int
    public let stepCount: Int
    /// The step on screen, from 0.
    public private(set) var index = 0

    /// What Next did.
    public enum Advance: Hashable, Sendable {
        /// Moved to the next step.
        case moved
        /// It was the last step, so the tour is finished.
        case finished
    }

    /// `nil` for a tour with no steps, which never shows.
    public init?(tour: TourID, version: Int, stepCount: Int) {
        guard stepCount > 0 else { return nil }
        self.tour = tour
        self.version = version
        self.stepCount = stepCount
    }

    public var isFirstStep: Bool { index == 0 }
    public var isLastStep: Bool { index == stepCount - 1 }

    /// Next, or the last step's own button ("Start styling" on Home).
    public mutating func next() -> Advance {
        guard !isLastStep else { return .finished }
        index += 1
        return .moved
    }

    /// Back. Does nothing on the first step and returns false.
    @discardableResult
    public mutating func back() -> Bool {
        guard !isFirstStep else { return false }
        index -= 1
        return true
    }

    /// The record kept when the run ends.
    public func record(_ outcome: TourOutcome, at date: Date) -> TourRecord {
        TourRecord(tour: tour, version: version, outcome: outcome, date: date)
    }
}
