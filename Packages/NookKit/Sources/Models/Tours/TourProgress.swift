import Foundation

// First-use quick tours (Phase 16a, PRD §7.8, FR-73, TourProgress / TourPreferences in §12).
//
// What's stored is a local preference: which tours she has seen, at which content version, how
// each one ended, and whether tours start on their own. No wardrobe content, no body values and
// no analytics identifier. Stage A keeps it in memory (`InMemoryTourProgressStore`); Phase 21a
// puts it on disk with the other preferences, and Delete my data erases it with her profile.

/// A tour's stable, logical name. Every layout of a screen shares one ID, so turning the phone,
/// changing the text size or moving to an iPad never counts as a new first visit.
public struct TourID: RawRepresentable, Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Home's tour: the laptop, the wardrobe, the suitcase and the name sign.
    public static let home = TourID("home")

    public static func < (lhs: TourID, rhs: TourID) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { rawValue }
}

/// How a tour ended. Each one counts as seen (PRD §7.8).
public enum TourOutcome: String, CaseIterable, Codable, Sendable {
    /// She went through every step and tapped the last button.
    case finished
    /// Skip, Escape or the VoiceOver escape gesture, on any step.
    case skipped
    /// She tapped the highlighted control, which did what it always does.
    case controlActivated
}

/// One tour she has seen.
public struct TourRecord: Hashable, Codable, Sendable {
    public var tour: TourID
    /// The content version she saw. A tour's version goes up only when its controls or workflow
    /// really change, never for copy fixes, and a newer version can show once more.
    public var version: Int
    public var outcome: TourOutcome
    /// When it ended.
    public var date: Date

    public init(tour: TourID, version: Int, outcome: TourOutcome, date: Date) {
        self.tour = tour
        self.version = version
        self.outcome = outcome
        self.date = date
    }
}

/// Everything stored about tours: the seen records and the "Show tips on new screens" switch.
public struct TourProgress: Hashable, Codable, Sendable {
    /// The latest record for each tour.
    public var records: [TourID: TourRecord]
    /// "Show tips on new screens" (PRD §7.8), on by default. Off stops tours from starting on
    /// their own; replay from Profile (Phase 16b) still works.
    public var showsTipsOnNewScreens: Bool

    public init(records: [TourID: TourRecord] = [:], showsTipsOnNewScreens: Bool = true) {
        self.records = records
        self.showsTipsOnNewScreens = showsTipsOnNewScreens
    }

    /// A fresh install: nothing seen, tips on.
    public static let fresh = TourProgress()

    /// Keeps `record` as its tour's latest.
    public mutating func add(_ record: TourRecord) {
        records[record.tour] = record
    }
}

/// When a tour may start on its own.
public enum TourRules {
    /// True when a tour at `version` should start by itself: tips are on and she hasn't seen
    /// this version or a later one. Replay and the debug `-tour` flag don't ask.
    public static func startsAutomatically(_ tour: TourID, version: Int, progress: TourProgress) -> Bool {
        guard progress.showsTipsOnNewScreens else { return false }
        guard let seen = progress.records[tour] else { return true }
        return seen.version < version
    }
}

/// Where tour progress is kept. Features read and write it only through this protocol.
public protocol TourProgressStore: ErasableStore {
    func progress() async throws(StoreError) -> TourProgress
    /// Keeps how a tour ended, replacing any earlier record for the same tour.
    func record(_ record: TourRecord) async throws(StoreError)
    /// The "Show tips on new screens" switch (its row is Phase 16b).
    func setShowsTipsOnNewScreens(_ isOn: Bool) async throws(StoreError)
}
