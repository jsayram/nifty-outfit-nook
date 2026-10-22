import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Phase 32a: Closet and Saved Looks with 5,000 pieces, 2,000 saved looks (and 1,000 unsaved
/// results) and 500 try-on pictures (`ScaleData`). What she waits for when she opens a tab, types a
/// search, or switches Saved | All.
///
/// Every check prints a "SCALE" line with the fastest, median and slowest of five runs; the numbers
/// are in LOAD_TEST_REPORT.md (closet repo). The bounds are loose and are for catching a change
/// that makes something many times slower: each check takes the fastest run, and CI gets three
/// times as long (`SpeedCheck.limit`). Tests run as a Debug build on a simulator.
@MainActor
@Suite(.heavyMainActorWork)
struct ScaleBrowsingTests {
    private static let large = FixtureSet.large.data(now: TestTime.now, calendar: TestTime.calendar)
    private static let data = ScaleData.make(growing: large.garments, now: TestTime.now)

    /// The bound in milliseconds: as written on a dev Mac, three times that on CI.
    private func limit(_ milliseconds: Double) -> Double { SpeedCheck.isOnCI ? milliseconds * 3 : milliseconds }

    private func closet() -> ClosetModel {
        let model = ClosetModel()
        model.show(Self.data.garments, suitcases: Self.large.suitcases, profile: Self.large.profile, now: TestTime.now)
        return model
    }

    private func looks() -> SavedLooksModel {
        let model = SavedLooksModel(searchDelay: .zero)
        model.show(Self.data.looks, garments: Self.data.garments, now: TestTime.now)
        model.showPictures(Self.data.pictures)
        return model
    }

    @Test func theScaleDataIsTheSizeItSays() {
        #expect(Self.data.garments.count == 5_000)
        #expect(Self.data.looks.filter(\.isSaved).count == 2_000)
        #expect(Self.data.looks.filter { !$0.isSaved }.count == 1_000)
        #expect(Self.data.pictures.count == 500)
        #expect(Self.data.garments.filter { !$0.otherNames.isEmpty }.count > 600)
    }

    // MARK: Closet

    @Test func openingClosetIsFast() {
        var model = ClosetModel()
        let times = ScaleReport.measure("Closet opens, 5,000 pieces (grid prepared)") { model = closet() }
        #expect(model.items.count > 4_000)
        #expect(times.fastest < limit(2_000))
    }

    @Test func searchingClosetIsFast() throws {
        let model = closet()
        // A word in a piece's own name, then one only an "other name" has (Phase 21c).
        let named = try #require(Self.data.garments.first { !$0.otherNames.isEmpty })
        let otherWord = try #require(named.otherNames.first?.split(separator: " ").first.map(String.init))
        var worst = 0.0
        for (label, text) in [
            ("a word in the name", "soft"), ("two words", "beach house"), ("an other name's word", otherWord),
            ("a whole other name", named.otherNames[0]),
        ] {
            let times = ScaleReport.measure("Closet search, \(label) (\"\(text)\")") {
                model.clearFilters()
                model.searchText = text
                model.applySearchNow()
            }
            worst = max(worst, times.fastest)
        }
        model.clearFilters()
        #expect(worst < limit(500))
    }

    @Test func possibleMatchesAreFast() {
        let model = closet()
        // Words that no single piece has all of, so the search finds nothing and offers the pieces
        // that have most of them (Phase 21c).
        var possible = 0
        var worst = 0.0
        for text in ["navy trousers party", "soft beach house tee", "olive cardigan wedding"] {
            let times = ScaleReport.measure("Closet possible matches (\"\(text)\")") {
                model.clearFilters()
                model.searchText = text
                model.applySearchNow()
                possible = max(possible, model.possible.count)
            }
            worst = max(worst, times.fastest)
        }
        ScaleReport.note("Closet possible matches offered up to \(possible) pieces")
        #expect(worst < limit(2_500))
    }

    @Test func eachChipSwatchAndFilterIsFast() {
        let model = closet()
        var worst = 0.0
        let steps: [(String, () -> Void)] = [
            ("a piece chip", { model.toggle(.top) }), ("a colour swatch", { model.toggle(.navy) }),
            ("in a suitcase", { model.setPacking(.inASuitcase) }), ("clear", { model.clearFilters() }),
        ]
        for (label, step) in steps {
            let times = ScaleReport.measure("Closet \(label)") { step() }
            worst = max(worst, times.fastest)
        }
        model.clearFilters()
        #expect(worst < limit(1_000))
    }

    // MARK: Saved Looks

    @Test func openingSavedLooksIsFast() {
        var model = SavedLooksModel(searchDelay: .zero)
        let times = ScaleReport.measure("Saved Looks opens, 2,000 saved + 1,000 unsaved looks, 500 pictures") {
            model = looks()
        }
        #expect(model.shown.count == 2_000)
        #expect(times.fastest < limit(2_000))
    }

    @Test func switchingSavedAndAllIsFast() {
        let model = looks()
        let toAll = ScaleReport.measure("Saved Looks: Saved to All") {
            model.scope = .all
            model.scope = .saved
        }
        #expect(model.shown.count == 2_000)
        model.scope = .all
        #expect(model.shown.count == 3_000)
        model.scope = .saved
        // Both directions are timed together above; this times one switch to All and one back.
        let all = ScaleReport.measure("Saved Looks: one switch to All, then back") {
            model.scope = .all
            model.scope = .saved
        }
        #expect(toAll.fastest < limit(1_000) && all.fastest < limit(1_000))
    }

    @Test func searchingSavedLooksInEachScopeIsFast() {
        let model = looks()
        var worst = 0.0
        // All first, then Saved, then All again: the same work in a different order shows whether a
        // difference is the scope or the machine (other work on the Mac moves a timing).
        for (pass, scope) in [SavedLooksModel.Scope.all, .saved, .all, .saved].enumerated() {
            model.scope = scope
            for text in ["navy", "blouse jeans", "Look 40", "soft"] {
                let times = ScaleReport.measure(
                    "Saved Looks search in \(scope.rawValue), pass \(pass + 1) (\"\(text)\")"
                ) {
                    model.searchText = ""
                    model.applySearchNow()
                    model.searchText = text
                    model.applySearchNow()
                }
                worst = max(worst, times.fastest)
            }
        }
        model.searchText = ""
        model.applySearchNow()
        #expect(worst < limit(1_000))
    }

    @Test func pictureSearchAndTabSwitchAreFast() {
        let model = looks()
        let times = ScaleReport.measure("Saved Looks: Pictures tab and back") {
            model.tab = .pictures
            model.tab = .looks
        }
        model.tab = .pictures
        model.searchText = "navy"
        model.applySearchNow()
        let search = ScaleReport.measure("Pictures search (\"navy\")") {
            model.searchText = "blouse"
            model.applySearchNow()
            model.searchText = "navy"
            model.applySearchNow()
        }
        #expect(times.fastest < limit(1_000) && search.fastest < limit(1_000))
    }
}
