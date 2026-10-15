import Foundation

/// Something that stops a hand-made or hand-changed look from being a look.
public enum LookProblem: Hashable, Sendable {
    /// A look has 2 to 6 pieces (RD-07.1).
    case tooFewPieces
    case tooManyPieces
    /// No dress, and not both a top and a bottom.
    case needsMainPieces
    /// Two pieces of one kind. Make your own look holds one of each kind.
    case twoOfAKind(GarmentCategory)
    /// A piece she can't wear from this source right now, with why.
    case notUsable(Garment.ID, [IneligibilityReason])
}

/// The checks for a look she builds or changes by hand: Make your own look, and Remove this
/// piece in Swap (LR-08).
///
/// These are shape and ownership checks on stored facts, the same kind `ResultCheck` makes for
/// a stylist's result. They say nothing about taste: any top goes with any bottom here. The one
/// shape rule, "a dress, or a top and a bottom", is the same one the mock stylist builds from.
public enum LookRules {
    /// How many pieces a look has (RD-07.1).
    public static let pieceRange = ResultCheck.pieceRange

    /// The kinds that make an outfit on their own: a dress, or a top with a bottom.
    public static func hasMainPieces(_ categories: [GarmentCategory]) -> Bool {
        categories.contains(.dress) || (categories.contains(.top) && categories.contains(.bottom))
    }

    /// Every shape problem with a look made of pieces of these kinds, in a fixed order.
    ///
    /// - Parameter onePerKind: Make your own look holds one piece of each kind. A stylist's look
    ///   changed in Swap is only checked for count and main pieces.
    public static func shapeProblems(of categories: [GarmentCategory], onePerKind: Bool) -> [LookProblem] {
        var problems: [LookProblem] = []
        if categories.count < pieceRange.lowerBound { problems.append(.tooFewPieces) }
        if categories.count > pieceRange.upperBound { problems.append(.tooManyPieces) }
        if !hasMainPieces(categories) { problems.append(.needsMainPieces) }
        if onePerKind {
            var seen: Set<GarmentCategory> = []
            for category in categories.sorted() where !seen.insert(category).inserted {
                if !problems.contains(.twoOfAKind(category)) { problems.append(.twoOfAKind(category)) }
            }
        }
        return problems
    }

    /// Every problem with a look she built from these garments, in this source, today.
    ///
    /// - Parameters:
    ///   - members: the suitcase's garment IDs when the look is from a suitcase, `nil` for the
    ///     main closet.
    ///   - tracksLaundry: with tracking on, a piece in the wash can't be used (RD-11).
    public static func problems(
        building garments: [Garment],
        members: Set<Garment.ID>?,
        tracksLaundry: Bool,
        on date: Date
    ) -> [LookProblem] {
        var problems = shapeProblems(of: garments.map(\.category), onePerKind: true)
        for garment in garments {
            let reasons = Eligibility.reasons(for: garment, members: members, tracksLaundry: tracksLaundry, on: date)
            if !reasons.isEmpty { problems.append(.notUsable(garment.id, reasons)) }
        }
        return problems
    }
}
