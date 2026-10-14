import Foundation

/// Why a garment can't be used for styling right now.
public enum IneligibilityReason: String, CaseIterable, Hashable, Sendable, Codable {
    /// On the wishlist. Wishlist pieces never count as owned (FR-37, LR-12).
    case notOwned
    /// "I don't have it any more" (LR-16).
    case noLongerOwned
    /// Bought but not arrived, or arrival unknown (PRD §8.1).
    case notArrived
    /// In Recently deleted.
    case deleted
    case archived
    /// Marked unavailable and not back yet.
    case unavailable
    /// Dirty, and laundry tracking is on (RD-11).
    case dirty
    /// Not in the suitcase being styled from.
    case outsideSource
}

/// Which garments Style Me, swaps and suitcase styling may use.
///
/// These are the strict ownership and availability rules from PRD §8.1 and RD-11, not styling
/// taste. Every version of every result must use only eligible pieces.
public enum Eligibility {
    /// The reasons a garment can't be styled, empty when it can.
    ///
    /// - Parameters:
    ///   - members: the suitcase's garment IDs when styling from a suitcase, `nil` for the main closet.
    ///   - tracksLaundry: with tracking off, a piece stored as Dirty is eligible (RD-11.2).
    ///   - date: the day of the request, for "unavailable until".
    public static func reasons(
        for garment: Garment,
        members: Set<Garment.ID>?,
        tracksLaundry: Bool,
        on date: Date
    ) -> [IneligibilityReason] {
        var reasons: [IneligibilityReason] = []
        switch garment.ownership {
        case .owned: break
        case .purchased(let arrival): if arrival != .arrived { reasons.append(.notArrived) }
        case .wishlisted: reasons.append(.notOwned)
        case .noLongerOwned: reasons.append(.noLongerOwned)
        }
        if garment.isDeleted { reasons.append(.deleted) }
        if garment.isArchived { reasons.append(.archived) }
        if case .unavailable(let until) = garment.availability, until.map({ $0 > date }) ?? true {
            reasons.append(.unavailable)
        }
        if tracksLaundry && garment.laundry == .dirty { reasons.append(.dirty) }
        if let members, !members.contains(garment.id) { reasons.append(.outsideSource) }
        return reasons
    }

    public static func isEligible(
        _ garment: Garment,
        members: Set<Garment.ID>?,
        tracksLaundry: Bool,
        on date: Date
    ) -> Bool {
        reasons(for: garment, members: members, tracksLaundry: tracksLaundry, on: date).isEmpty
    }

    /// The eligible garments, in the order given.
    public static func eligible(
        _ garments: [Garment],
        members: Set<Garment.ID>?,
        tracksLaundry: Bool,
        on date: Date
    ) -> [Garment] {
        garments.filter { isEligible($0, members: members, tracksLaundry: tracksLaundry, on: date) }
    }
}
