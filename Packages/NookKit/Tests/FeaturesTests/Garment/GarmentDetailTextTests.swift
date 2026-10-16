import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// The words on garment detail, with a fixed clock, calendar and locale (LR-10, RD-11, LR-16).
@MainActor
struct GarmentDetailTextTests {
    private func piece(
        _ category: GarmentCategory = .top,
        worn: [Int] = [],
        laundry: LaundryState = .clean,
        availability: Availability = .available,
        ownership: Ownership = .owned,
        configure: (inout Garment) -> Void = { _ in }
    ) -> Garment {
        var garment = Garment(
            id: "g-test", name: "Test piece", category: category, ownership: ownership, laundry: laundry,
            availability: availability, wornOn: worn.map(TestTime.day), addedAt: TestTime.day(-400))
        configure(&garment)
        return garment
    }

    private func text(
        _ garment: Garment,
        tracksLaundry: Bool = false,
        repeatWindow: RepeatWindow = .oneWeek,
        now: Date = TestTime.now
    ) -> GarmentDetailText {
        GarmentDetailText(
            garment: garment, tracksLaundry: tracksLaundry, repeatWindow: repeatWindow, now: now,
            calendar: TestTime.calendar, locale: TestTime.locale)
    }

    // MARK: Last worn (LR-10)

    @Test func lastWornCountsCalendarDaysThenGivesTheDate() {
        #expect(text(piece(worn: [0])).lastWorn == "Last worn today")
        #expect(text(piece(worn: [-1])).lastWorn == "Last worn yesterday")
        #expect(text(piece(worn: [-200, -5])).lastWorn == "Last worn 5 days ago")
        #expect(text(piece(worn: [-7])).lastWorn == "Last worn Oct 7")
        #expect(text(piece(worn: [-300])).lastWorn == "Last worn Dec 18, 2025")
    }

    @Test func lateLastNightIsYesterday() {
        let calendar = TestTime.calendar
        let today = calendar.startOfDay(for: TestTime.now)
        var garment = piece()
        garment.wornOn = [today.addingTimeInterval(-30 * 60)]
        #expect(text(garment, now: today.addingTimeInterval(30 * 60)).lastWorn == "Last worn yesterday")
    }

    @Test func neverMarkedAsWorn() {
        #expect(text(piece()).lastWorn == "Not marked as worn yet")
        #expect(text(piece()).recentWearNote == nil)
    }

    // MARK: The recent-wear note (LR-10)

    @Test func aMainPieceWornInsideTheWindowGetsTheNote() {
        let worn = text(piece(.top, worn: [-5]))
        #expect(worn.isWornRecently)
        #expect(worn.recentWearNote == "Style Me won’t repeat an outfit you wore it in during the last week.")
        #expect(text(piece(.dress, worn: [0])).isWornRecently)
        #expect(text(piece(.bottom, worn: [-6])).isWornRecently)
    }

    /// One week is today and the 6 days before, so a week ago is outside it.
    @Test func aWeekAgoIsOutsideOneWeek() {
        #expect(!text(piece(.top, worn: [-7])).isWornRecently)
        #expect(text(piece(.top, worn: [-7])).recentWearNote == nil)
    }

    @Test func twoWeeksNamesItsWindow() {
        let worn = text(piece(.bottom, worn: [-10]), repeatWindow: .twoWeeks)
        #expect(worn.recentWearNote == "Style Me won’t repeat an outfit you wore it in during the last 2 weeks.")
        #expect(text(piece(.bottom, worn: [-14]), repeatWindow: .twoWeeks).recentWearNote == nil)
    }

    /// LR-10.3: "I don't mind" makes nothing recent.
    @Test func iDontMindHasNoNote() {
        #expect(text(piece(.top, worn: [0]), repeatWindow: .noLimit).recentWearNote == nil)
    }

    /// Shoes, layers, bags and accessories can repeat freely (LR-10).
    @Test func piecesThatCanRepeatHaveNoNote() {
        for category in [GarmentCategory.shoes, .layer, .bag, .accessory] {
            #expect(text(piece(category, worn: [-1])).recentWearNote == nil, "\(category)")
        }
    }

    // MARK: Status (RD-11)

    @Test func statusWithTrackingOff() {
        #expect(text(piece()).status == "Available")
        // A Dirty mark is kept but doesn't show while tracking is off (RD-11.1).
        #expect(text(piece(laundry: .dirty)).status == "Available")
        #expect(!text(piece(laundry: .dirty)).isInTheWash)
    }

    @Test func statusWithTrackingOn() {
        #expect(text(piece(), tracksLaundry: true).status == "Clean")
        #expect(text(piece(laundry: .dirty), tracksLaundry: true).status == "Dirty")
        #expect(text(piece(laundry: .dirty), tracksLaundry: true).isInTheWash)
    }

    @Test func statusWhenAwayOrNotHereYet() {
        #expect(text(piece(availability: .unavailable(until: TestTime.day(9)))).status == "Away until Oct 23")
        #expect(text(piece(availability: .unavailable(until: nil))).status == "Away for now")
        // Back already: the date has passed.
        #expect(text(piece(availability: .unavailable(until: TestTime.day(-1)))).status == "Available")
        #expect(text(piece(ownership: .purchased(.notArrived))).status == "Bought, not here yet")
        #expect(text(piece(ownership: .purchased(.arrived))).status == "Available")
        #expect(
            text(piece(laundry: .dirty, availability: .unavailable(until: nil)), tracksLaundry: true).status
                == "Away for now · Dirty")
        #expect(text(piece(ownership: .noLongerOwned)).status == "No longer in your closet")
    }

    // MARK: Facts

    @Test func factsInPlainWords() {
        let dress = piece(.dress) { garment in
            garment.colors = [.blue, .white]
            garment.colorNote = "Cornflower blue floral"
            garment.fit = .regular
            garment.seasons = [.summer, .spring]
            garment.occasions = [.event, .dateNight, .brunch]
            garment.brand = "  Demo Store "
            garment.sizeLabel = "XS"
            garment.notes = "At the tailor"
        }
        let words = text(dress)
        #expect(words.kind == "Dresses")
        #expect(words.colors == "Blue, White")
        #expect(words.colorNote == "Cornflower blue floral")
        #expect(words.fit == "Regular")
        #expect(words.seasons == "Spring, Summer")
        #expect(words.occasions == "Brunch, Date night, Event")
        #expect(words.brand == "Demo Store")
        #expect(words.size == "XS")
        #expect(words.notes == "At the tailor")
    }

    @Test func unknownFactsAreLeftOut() {
        let bare = piece { garment in
            garment.seasons = []
            garment.notes = "   "
        }
        let words = text(bare)
        #expect(words.colors == nil)
        #expect(words.colorNote == nil)
        #expect(words.fit == nil)
        #expect(words.seasons == nil)
        #expect(words.occasions == nil)
        #expect(words.brand == nil)
        #expect(words.notes == nil)
        // Every season reads as all year.
        #expect(text(piece()).seasons == "All year")
    }

    @Test func savedLooksCount() {
        let words = text(piece())
        #expect(words.savedLooks(0) == "Not in a saved look yet")
        #expect(words.savedLooks(1) == "In 1 saved look")
        #expect(words.savedLooks(3) == "In 3 saved looks")
    }

    /// PRD §7.4: Recently deleted keeps a piece for 30 days.
    @Test func deletionDeadlineIsThirtyDaysOn() {
        #expect(text(piece()).deletionDeadline == "Nov 13")
        let lateDecember = TestTime.day(70)
        #expect(text(piece(), now: lateDecember).deletionDeadline == "Jan 22, 2027")
    }
}
