import Foundation

/// Something wrong with a styling result. A result with any problem is not shown.
public enum ResultProblem: Hashable, Sendable {
    case noSimpleVersion
    case repeatedVersion(LookVersion)
    /// A look must have 2 to 6 pieces (RD-07.1).
    case pieceCount(LookVersion)
    case repeatedPiece(Garment.ID, LookVersion)
    /// An owned piece that isn't in the eligible set for this request.
    case notEligible(Garment.ID, LookVersion)
    /// An unowned piece where none is allowed: Only mine, a suitcase source, or not Something new.
    case ideaNotAllowed(LookVersion)
    case moreThanOneIdea(LookVersion)
    case missingStartingPiece(LookVersion)
    /// Dressed up and Something new must keep at least one piece from Simple (LR-05a.1).
    case sharesNothingWithSimple(LookVersion)
    /// A piece is marked "Same as Simple" but isn't in Simple, or the other way round.
    case wrongSameAsSimpleMark(LookVersion)
}

/// Checks a stylist's result against the request before the app shows it.
///
/// The PRD has the client validate every result, whichever stylist made it (§8). These are the
/// ownership, scope and shape rules only, not taste.
public enum ResultCheck {
    public static let pieceRange = 2...6

    /// Every problem found. Empty means the result can be shown.
    public static func problems(in result: StyleResult, for context: StylingContext) -> [ResultProblem] {
        var problems: [ResultProblem] = []
        let eligible = Set(context.eligibleGarments.map(\.id))
        let request = context.request
        guard let simple = result.simple else { return [.noSimpleVersion] }
        let simpleIDs = Set(simple.garmentIDs)

        var seenVersions: Set<LookVersion> = []
        for look in result.versions {
            guard let version = look.version else { continue }
            if !seenVersions.insert(version).inserted { problems.append(.repeatedVersion(version)) }
            if !pieceRange.contains(look.pieces.count) { problems.append(.pieceCount(version)) }

            var seenPieces: Set<Garment.ID> = []
            for id in look.garmentIDs {
                if !seenPieces.insert(id).inserted { problems.append(.repeatedPiece(id, version)) }
                if !eligible.contains(id) { problems.append(.notEligible(id, version)) }
            }

            let ideas = look.ideas.count
            if ideas > 0 && (!request.allowsNewPieceIdea || version != .somethingNew) {
                problems.append(.ideaNotAllowed(version))
            }
            if ideas > 1 { problems.append(.moreThanOneIdea(version)) }

            if let start = request.startingPieceID, !seenPieces.contains(start) {
                problems.append(.missingStartingPiece(version))
            }

            if version != .simple && seenPieces.isDisjoint(with: simpleIDs) {
                problems.append(.sharesNothingWithSimple(version))
            }
            let marksAreRight = look.pieces.allSatisfy { piece in
                let inSimple = piece.garmentID.map(simpleIDs.contains) ?? false
                return piece.isSameAsSimple == (version == .simple ? piece.garmentID != nil : inSimple)
            }
            if !marksAreRight { problems.append(.wrongSameAsSimpleMark(version)) }
        }
        return problems
    }
}
