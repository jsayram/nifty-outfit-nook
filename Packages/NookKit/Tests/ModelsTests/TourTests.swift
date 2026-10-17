import Foundation
import Models
import Testing

/// Quick tours (Phase 16a, PRD §7.8): stepping through a run, what it records, and when a tour
/// may start by itself.
struct TourTests {
    @Test func nextWalksEveryStepThenFinishes() throws {
        var run = try #require(TourRun(tour: .home, version: 1, stepCount: 4))
        #expect(run.index == 0)
        #expect(run.isFirstStep)
        var moves: [TourRun.Advance] = []
        for _ in 0..<3 { moves.append(run.next()) }
        #expect(moves == [.moved, .moved, .moved])
        #expect(run.index == 3)
        #expect(run.isLastStep)
        // The last step's button finishes and stays on the last step.
        let last = run.next()
        #expect(last == .finished)
        #expect(run.index == 3)
    }

    @Test func backStopsAtTheFirstStep() throws {
        var run = try #require(TourRun(tour: .home, version: 1, stepCount: 4))
        let backFromFirst = run.back()
        #expect(!backFromFirst)
        #expect(run.index == 0)
        _ = run.next()
        _ = run.next()
        let backFromThird = run.back()
        #expect(backFromThird)
        #expect(run.index == 1)
    }

    @Test func aOneStepTourFinishesOnItsFirstNext() throws {
        var run = try #require(TourRun(tour: TourID("tiny"), version: 1, stepCount: 1))
        #expect(run.isFirstStep && run.isLastStep)
        let advance = run.next()
        #expect(advance == .finished)
    }

    @Test func aTourWithNoStepsNeverRuns() {
        #expect(TourRun(tour: .home, version: 1, stepCount: 0) == nil)
    }

    @Test func theRecordKeepsTheVersionAndHowItEnded() throws {
        let run = try #require(TourRun(tour: .home, version: 3, stepCount: 4))
        let date = Date(timeIntervalSince1970: 1_000)
        let record = run.record(.skipped, at: date)
        #expect(record == TourRecord(tour: .home, version: 3, outcome: .skipped, date: date))
    }

    @Test func anUnseenTourStartsWhileTipsAreOn() {
        #expect(TourRules.startsAutomatically(.home, version: 1, progress: .fresh))
        let off = TourProgress(showsTipsOnNewScreens: false)
        #expect(!TourRules.startsAutomatically(.home, version: 1, progress: off))
    }

    /// Finished, skipped and ended by the control all count as seen (PRD §7.8).
    @Test(arguments: TourOutcome.allCases)
    func aSeenTourDoesNotStartAgain(outcome: TourOutcome) {
        var progress = TourProgress.fresh
        progress.add(TourRecord(tour: .home, version: 1, outcome: outcome, date: .distantPast))
        #expect(!TourRules.startsAutomatically(.home, version: 1, progress: progress))
        // Another tour is unaffected.
        #expect(TourRules.startsAutomatically(TourID("closet"), version: 1, progress: progress))
    }

    /// A new version shows once more, but only while tips are on.
    @Test func aNewVersionStartsOnceMore() {
        var progress = TourProgress.fresh
        progress.add(TourRecord(tour: .home, version: 1, outcome: .finished, date: .distantPast))
        #expect(TourRules.startsAutomatically(.home, version: 2, progress: progress))
        progress.add(TourRecord(tour: .home, version: 2, outcome: .skipped, date: .distantPast))
        #expect(!TourRules.startsAutomatically(.home, version: 2, progress: progress))
        progress.showsTipsOnNewScreens = false
        #expect(!TourRules.startsAutomatically(.home, version: 3, progress: progress))
    }

    @Test func aRecordReplacesTheTourEarlierOne() {
        var progress = TourProgress.fresh
        progress.add(TourRecord(tour: .home, version: 1, outcome: .skipped, date: .distantPast))
        progress.add(TourRecord(tour: .home, version: 2, outcome: .finished, date: .distantFuture))
        #expect(progress.records.count == 1)
        #expect(progress.records[.home]?.version == 2)
    }

    /// Phase 16b: every tour has its own stable ID, and Reset all tips forgets them all.
    @Test func everyTourHasItsOwnIDAndResetForgetsThemAll() {
        #expect(Set(TourID.all).count == TourID.all.count)
        // 20 from Phase 16b, and six more from the Stage A audit.
        #expect(TourID.all.count == 26)
        #expect(TourID.all.first == .home)
        var progress = TourProgress(showsTipsOnNewScreens: false)
        for tour in TourID.all {
            progress.add(TourRecord(tour: tour, version: 1, outcome: .finished, date: .distantPast))
        }
        progress.forgetSeen()
        #expect(progress.records.isEmpty)
        #expect(progress.seenVersions.isEmpty)
        #expect(!progress.showsTipsOnNewScreens)
        // Seen nothing, but tips off: still nothing starts by itself.
        #expect(!TourRules.startsAutomatically(.closet, version: 1, progress: progress))
    }

    /// Phase 17: the seen versions are what's kept across launches, so a tour seen before this
    /// session doesn't start again, though this session has no record of how it ended.
    @Test func versionsSeenBeforeThisSessionCount() {
        let earlier = TourProgress(seenVersions: [.home: 1, .closet: 2])
        #expect(earlier.records.isEmpty)
        #expect(!TourRules.startsAutomatically(.home, version: 1, progress: earlier))
        #expect(TourRules.startsAutomatically(.home, version: 2, progress: earlier))
        #expect(!TourRules.startsAutomatically(.closet, version: 2, progress: earlier))
        #expect(TourRules.startsAutomatically(.styleMe, version: 1, progress: earlier))
    }

    @Test func recordsCountAsSeenAndKeepTheHighestVersion() {
        let record = TourRecord(tour: .home, version: 3, outcome: .skipped, date: .distantPast)
        let progress = TourProgress(records: [.home: record], seenVersions: [.home: 1, .fit: 1])
        #expect(progress.seenVersions == [.home: 3, .fit: 1])
        var later = progress
        later.add(TourRecord(tour: .home, version: 2, outcome: .finished, date: .distantFuture))
        #expect(later.seenVersions[.home] == 3)
        #expect(later.records[.home]?.version == 2)
    }
}
