import Foundation
import Models
import Testing

struct EligibilityTests {
    private func reasons(
        _ garment: Garment,
        members: Set<Garment.ID>? = nil,
        tracksLaundry: Bool = false
    ) -> [IneligibilityReason] {
        Eligibility.reasons(for: garment, members: members, tracksLaundry: tracksLaundry, on: TestTime.now)
    }

    @Test func anOwnedCleanPieceIsEligible() {
        #expect(reasons(Make.garment("g-1", .top)).isEmpty)
    }

    @Test(arguments: [
        (Ownership.wishlisted, [IneligibilityReason.notOwned]),
        (.noLongerOwned, [.noLongerOwned]),
        (.purchased(.notArrived), [.notArrived]),
        (.purchased(.unknown), [.notArrived]),
        (.purchased(.arrived), []),
    ])
    func ownershipDecidesFirst(ownership: Ownership, expected: [IneligibilityReason]) {
        #expect(reasons(Make.garment("g-1", .top, ownership: ownership)) == expected)
    }

    @Test func dirtyCountsOnlyWhileTrackingLaundry() {
        let dirty = Make.garment("g-1", .top, laundry: .dirty)
        #expect(reasons(dirty, tracksLaundry: false).isEmpty)  // RD-11.2
        #expect(reasons(dirty, tracksLaundry: true) == [.dirty])
    }

    @Test func unavailableUntilADateComesBackThatDay() {
        var garment = Make.garment("g-1", .top)
        garment.availability = .unavailable(until: TestTime.day(2))
        #expect(reasons(garment) == [.unavailable])
        garment.availability = .unavailable(until: TestTime.day(-1))
        #expect(reasons(garment).isEmpty)
        garment.availability = .unavailable(until: nil)
        #expect(reasons(garment) == [.unavailable])
    }

    @Test func archivedAndDeletedPiecesAreNotStyled() {
        var garment = Make.garment("g-1", .top)
        garment.isArchived = true
        garment.deletedAt = TestTime.day(-1)
        #expect(reasons(garment) == [.deleted, .archived])
    }

    @Test func aSuitcaseOnlyUsesItsOwnPieces() {
        let garment = Make.garment("g-1", .top)
        #expect(reasons(garment, members: ["g-1"]).isEmpty)
        #expect(reasons(garment, members: ["g-2"]) == [.outsideSource])
        #expect(reasons(garment, members: []) == [.outsideSource])
    }

    @Test func aWishlistPieceInASuitcaseIsStillNotOwned() {
        // LR-12.1: a wishlist piece is never offered as owned, suitcase or not.
        let garment = Make.garment("g-1", .top, ownership: .wishlisted)
        #expect(reasons(garment, members: ["g-1"]) == [.notOwned])
    }

    @Test func eligibleKeepsTheGivenOrder() {
        let garments = [
            Make.garment("g-3", .top),
            Make.garment("g-1", .top, ownership: .wishlisted),
            Make.garment("g-2", .top),
        ]
        let eligible = Eligibility.eligible(garments, members: nil, tracksLaundry: false, on: TestTime.now)
        #expect(eligible.map(\.id) == ["g-3", "g-2"])
    }
}

struct HamperTests {
    private let garments = [
        Make.garment("g-1", .top, laundry: .dirty),
        Make.garment("g-2", .top, laundry: .dirty),
        Make.garment("g-3", .top),
        Make.garment("g-4", .top, ownership: .noLongerOwned, laundry: .dirty),
    ]

    @Test func trackingOffShowsTheQuietHamper() {
        #expect(HamperState(garments: garments, tracksLaundry: false) == .off)
    }

    @Test func countsDirtyPiecesInTheCloset() {
        #expect(HamperState(garments: garments, tracksLaundry: true) == .toWash(2))
    }

    @Test func allCleanWhenNothingIsDirty() {
        #expect(HamperState(garments: [Make.garment("g-1", .top)], tracksLaundry: true) == .allClean)
        #expect(HamperState(garments: [], tracksLaundry: true) == .allClean)
    }
}
