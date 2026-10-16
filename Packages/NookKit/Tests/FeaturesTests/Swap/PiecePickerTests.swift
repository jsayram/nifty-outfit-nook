import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// The picker behind See all and Add a piece: Closet's model over a chosen set of pieces.
@MainActor
struct PiecePickerTests {
    private static let data = FixtureSet.demo.data(now: TestTime.now, calendar: TestTime.calendar)

    private func picker(_ scope: PieceScope, tracksLaundry: Bool = true) -> ClosetModel {
        let model = ClosetModel(scope: scope)
        model.show(
            Self.data.garments, suitcases: Self.data.suitcases,
            profile: Profile(preferences: Preferences(tracksLaundry: tracksLaundry)), now: TestTime.now)
        return model
    }

    @Test func showsOnlyTheScopeInItsOrderWithItsMarks() {
        let model = picker(
            PieceScope(
                garmentIDs: ["g-white-sneakers", "g-black-heels", "g-gray-leggings"],
                notes: ["g-white-sneakers": SwapText.mayNotMatch], fixedKind: .shoes))
        // The deleted leggings aren't in her closet, so they're left out even if asked for.
        #expect(model.shown.map(\.id) == ["g-white-sneakers", "g-black-heels"])
        #expect(model.shown.first?.note == SwapText.mayNotMatch)
        #expect(model.pieceKinds.isEmpty, "A fixed kind has no piece chips")
        #expect(!model.showsLaundryFilter)
        #expect(
            model.shown.first?.spokenDetails(
                now: TestTime.now, calendar: TestTime.calendar, locale: TestTime.locale
            )
            .hasPrefix("May not match") == true)
    }

    @Test func aPickerOfEveryKindHasChipsForWhatItHolds() {
        let model = picker(PieceScope(garmentIDs: ["g-pink-blouse", "g-navy-trousers", "g-nude-flats"]))
        #expect(model.pieceKinds == [.top, .bottom, .shoes])
        model.showOnly(.bottom)
        #expect(model.shown.map(\.id) == ["g-navy-trousers"])
        model.clearFilters()
        model.searchText = "pink"
        model.applySearchNow()
        #expect(model.shown.map(\.id) == ["g-pink-blouse"])
    }

    /// Closet itself is unchanged: every piece in her closet and the Dirty chip while tracking.
    @Test func closetKeepsItsOwnBehaviour() {
        let model = ClosetModel()
        model.show(
            Self.data.garments, suitcases: Self.data.suitcases,
            profile: Profile(preferences: Preferences(tracksLaundry: true)), now: TestTime.now)
        #expect(model.showsLaundryFilter)
        #expect(model.pieceKinds.starts(with: ClosetModel.standardKinds))
        #expect(model.items.allSatisfy { $0.note == nil })
    }
}
