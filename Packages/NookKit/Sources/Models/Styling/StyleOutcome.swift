import Foundation

/// What the stylist returns for one request (LR-05a, PRD §8 and §12 OutfitGenerationResult).
///
/// A failure to finish is not an outcome: the stylist throws `StylistError` instead, so a model
/// or network problem can never be shown as "your closet is too small".
public enum StyleOutcome: Hashable, Sendable, Codable {
    /// All three versions.
    case complete(StyleResult)
    /// One or two versions, because the closet couldn't support the others. Says which and why.
    case partial(StyleResult, missing: [MissingVersion])
    /// No valid outfit from the eligible pieces in this source.
    case insufficient(InsufficientWardrobe)

    /// The result to show, if there is one.
    public var result: StyleResult? {
        switch self {
        case .complete(let result), .partial(let result, _): result
        case .insufficient: nil
        }
    }
}

/// One base outfit in up to three versions, plus ranked owned alternatives for swapping.
///
/// Data tier: **Personal**.
public struct StyleResult: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<StyleResult>

    public let id: ID
    public var requestID: StyleRequest.ID
    /// In switch order: Simple, then Dressed up and Something new when present.
    public var versions: [Look]
    /// Other owned pieces for each piece slot of the Simple version, best first.
    public var alternates: [PieceAlternates]
    public var notes: [ResultNote]
    public var createdAt: Date

    public init(
        id: ID,
        requestID: StyleRequest.ID,
        versions: [Look],
        alternates: [PieceAlternates] = [],
        notes: [ResultNote] = [],
        createdAt: Date
    ) {
        self.id = id
        self.requestID = requestID
        self.versions = versions
        self.alternates = alternates
        self.notes = notes
        self.createdAt = createdAt
    }

    public func look(for version: LookVersion) -> Look? {
        versions.first { $0.version == version }
    }

    public var simple: Look? { look(for: .simple) }
}

/// Owned alternatives for one kind of piece, best first.
public struct PieceAlternates: Hashable, Sendable, Codable {
    public var category: GarmentCategory
    public var garmentIDs: [Garment.ID]

    public init(category: GarmentCategory, garmentIDs: [Garment.ID]) {
        self.category = category
        self.garmentIDs = garmentIDs
    }
}

/// A quiet line shown with a result.
public enum ResultNote: Hashable, Sendable, Codable {
    /// "You wore this last week" (LR-10): the look matches one worn inside the repeat window.
    case wornRecently(lastWorn: Date)
    /// Something new stayed owned-only because the source is a suitcase (LR-05b).
    case noNewPieceInSuitcase
    /// The weather couldn't be read, so the look ignores it (LR-04.3).
    case weatherUnavailable
    /// Try a different outfit found no new base: every outfit this source can make has been
    /// shown for this request, so this one comes round again.
    case noOtherOutfit
    /// She asked for a colour as required, and no usable piece could bring it into the look, so
    /// the look goes without it rather than inventing a piece (PRD §8.3).
    case requiredColorNotMet(ColorName)
    /// 27a, FR-58: an earlier result from her own history that still fits today's request, shown
    /// before asking the stylist again. New ideas asks afresh.
    case fromHistory
    /// 27a: the same request was asked in the last day, so the stylist's earlier answer came back
    /// from the server without asking again or using an allowance.
    case answeredAgain
}

/// A version the stylist couldn't make, and why. Shown with a partial result.
public struct MissingVersion: Hashable, Sendable, Codable {
    public var version: LookVersion
    public var reason: Reason

    public init(version: LookVersion, reason: Reason) {
        self.version = version
        self.reason = reason
    }

    public enum Reason: String, CaseIterable, Hashable, Sendable, Codable {
        /// No dressier piece she owns could replace one in the outfit.
        case noDressierPiece
        /// No other owned piece could make a different version.
        case noOtherOwnedPiece
    }
}

/// No valid outfit exists in this source. Lists what's missing, so the screen can say so.
public struct InsufficientWardrobe: Hashable, Sendable, Codable {
    public var source: WardrobeSource
    /// Kinds of piece with nothing eligible: for example shoes, or a bottom to go with the tops.
    public var missing: [GarmentCategory]

    public init(source: WardrobeSource, missing: [GarmentCategory]) {
        self.source = source
        self.missing = missing
    }
}

/// Why the stylist couldn't finish. Never a claim about her closet (LR-05a).
public enum StylistError: Error, Hashable, Sendable {
    /// The stylist ran but didn't produce a valid result (GenerationNotCompleted).
    case notCompleted
    /// No connection.
    case offline
    /// It took too long.
    case timedOut
    /// The request was cancelled, for example because she left the screen.
    case cancelled
    /// The request couldn't be built, for example because the starting piece isn't eligible.
    case invalidRequest(StylingContextError)
    /// 27a: she hasn't agreed to send styling requests to the stylist's provider, or withdrew it.
    /// Nothing was sent.
    case needsConsent
    /// 27a: a server limit stopped it (too many at once, an allowance used up, paused, this
    /// device not verified, signed out). Nothing was counted.
    case limited(CloudLimitProblem)
}
