import Foundation

/// What she has chosen on Style Me so far, before she taps Style me (RD-02).
///
/// Data tier: **Sensitive** while it holds today's comfort, otherwise **Personal**, like the
/// request it becomes. It lives only while the Style Me screen is open: a new Style Me starts
/// from `init(preferences:)` again, so Comfort, Color and Weather reset (RD-02.4, LR-04.2,
/// LR-18.2).
public struct StyleRequestDraft: Hashable, Sendable, Codable {
    public var source: WardrobeSource
    public var occasion: Occasion
    /// Her words for an Other occasion, as typed. Only used when `occasion` is `.other`.
    public var occasionNote: String
    /// "Style with this", or picked on Style Me.
    public var startingPieceID: Garment.ID?
    public var weatherChoice: WeatherChoice
    /// Today's comfort. `nil` means her usual fit.
    public var comfort: Comfort?
    public var color: ColorWish?
    /// Preferences (LR-03): starts from her saved choice and applies to this request.
    public var pieceMode: PieceMode

    /// A fresh request: the defaults are good enough to tap Style me straight away (RD-02).
    public init(
        preferences: Preferences,
        source: WardrobeSource = .mainCloset,
        occasion: Occasion = .office,
        startingPieceID: Garment.ID? = nil
    ) {
        self.source = source
        self.occasion = occasion
        occasionNote = ""
        self.startingPieceID = startingPieceID
        weatherChoice = .useToday
        comfort = nil
        color = nil
        pieceMode = preferences.pieceMode
    }
}

/// Something Style Me says about a request before it's sent. Some stop the Style me button
/// (`blocksStyling`); the rest are early warnings she can style past.
public enum StyleRequestIssue: Hashable, Sendable {
    /// Nothing in her closet yet. Style Me needs a few pieces first.
    case closetEmpty
    /// The suitcase is gone or archived. A missing source never quietly becomes the main closet
    /// (FR-67).
    case suitcaseMissing
    /// The suitcase has nothing packed (PRD §8.1: no invented pieces for an empty suitcase).
    case suitcaseEmpty
    /// Fewer usable pieces than the smallest look. `total` counts the pieces in the source,
    /// including those in the wash or away.
    case tooFewToStyle(usable: Int, total: Int)
    /// A warning: a suitcase with enough for a look, but probably not for all three versions.
    case fewPieces(usable: Int)
    /// The starting piece isn't in the closet's records any more.
    case startingPieceMissing
    /// The starting piece can't be used for this request, and why.
    case startingPieceUnusable([IneligibilityReason])
    /// Her words for Other are too long or have line breaks.
    case occasionNoteInvalid(NameProblem)
    /// A warning: a required colour that no usable piece in the source has where she asked.
    case requiredColorUnavailable(ColorWish)

    public var blocksStyling: Bool {
        switch self {
        case .fewPieces, .requiredColorUnavailable: false
        case .closetEmpty, .suitcaseMissing, .suitcaseEmpty, .tooFewToStyle, .startingPieceMissing,
            .startingPieceUnusable, .occasionNoteInvalid:
            true
        }
    }
}

/// The result of checking a draft: the issues, and the piece counts the screen shows.
public struct StyleRequestCheck: Hashable, Sendable {
    /// In a fixed order: the source first, then the starting piece, the occasion and the colour.
    public var issues: [StyleRequestIssue]
    /// Pieces in the source that are in her closet, usable or not.
    public var piecesInSource: Int
    /// Pieces in the source Style Me may use today (`Eligibility`).
    public var usablePieces: Int

    public init(issues: [StyleRequestIssue], piecesInSource: Int, usablePieces: Int) {
        self.issues = issues
        self.piecesInSource = piecesInSource
        self.usablePieces = usablePieces
    }

    /// True when nothing stops the Style me button.
    public var canStyle: Bool { !issues.contains { $0.blocksStyling } }

    public var blockingIssues: [StyleRequestIssue] { issues.filter(\.blocksStyling) }
    public var warnings: [StyleRequestIssue] { issues.filter { !$0.blocksStyling } }
}

/// Why `StyleRequestBuilder.build` made no request.
public enum StyleRequestError: Error, Hashable, Sendable {
    case cannotStyle([StyleRequestIssue])
}

/// Checks a Style Me draft against her closet and turns it into a `StyleRequest` (RD-02).
///
/// Pure and synchronous: it takes everything it needs, so a screen can re-check on every change
/// and tests can try any combination. The rules are ownership and availability facts
/// (`Eligibility`) and counts, never styling taste. Anything it lets through also passes
/// `StylingContext.make`.
public struct StyleRequestBuilder: Sendable {
    /// The smallest look: a result needs at least this many usable pieces (`ResultCheck`).
    public static let minimumPieces = ResultCheck.pieceRange.lowerBound
    /// Below this many usable pieces, a suitcase probably can't give all three versions: a base
    /// outfit plus a dressier and another piece to swap in. A heads-up only, not a rule.
    public static let fullResultPieces = 6

    public let garments: [Garment]
    public let suitcases: [Suitcase]
    /// Her saved preferences. Laundry tracking and the repeat window come from here; the piece
    /// mode comes from the draft.
    public let preferences: Preferences
    /// The day of the request, for "unavailable until".
    public let now: Date

    private let garmentsByID: [Garment.ID: Garment]

    public init(garments: [Garment], suitcases: [Suitcase], preferences: Preferences, now: Date) {
        self.garments = garments
        self.suitcases = suitcases
        self.preferences = preferences
        self.now = now
        garmentsByID = Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Sources

    /// The suitcases she can style from: not archived, by name.
    public var activeSuitcases: [Suitcase] {
        suitcases.filter { !$0.isArchived }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The suitcase a source names, if it exists and isn't archived.
    public func suitcase(for source: WardrobeSource) -> Suitcase? {
        guard let id = source.suitcaseID else { return nil }
        return suitcases.first { $0.id == id && !$0.isArchived }
    }

    /// Pieces in the source that are in her closet, whether or not they can be used today.
    /// Empty for a missing suitcase.
    public func pieces(in source: WardrobeSource) -> [Garment] {
        let inCloset = garments.filter(\.isInCloset)
        guard source.isSuitcase else { return inCloset }
        guard let suitcase = suitcase(for: source) else { return [] }
        return inCloset.filter { suitcase.contains($0.id) }
    }

    /// Pieces in the source that Style Me may use today, by name: the starting piece choices.
    public func usablePieces(in source: WardrobeSource) -> [Garment] {
        Eligibility.eligible(
            pieces(in: source), members: suitcase(for: source)?.garmentIDs, tracksLaundry: preferences.tracksLaundry,
            on: now
        )
        .sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    /// The starting piece, if it's still in her records.
    public func garment(_ id: Garment.ID) -> Garment? {
        garmentsByID[id]
    }

    // MARK: Checking

    public func check(_ draft: StyleRequestDraft) -> StyleRequestCheck {
        var members: Set<Garment.ID>?
        if draft.source.isSuitcase {
            guard let suitcase = suitcase(for: draft.source) else {
                return StyleRequestCheck(issues: [.suitcaseMissing], piecesInSource: 0, usablePieces: 0)
            }
            members = suitcase.garmentIDs
        }
        let inSource = pieces(in: draft.source)
        if inSource.isEmpty {
            let issue: StyleRequestIssue = draft.source.isSuitcase ? .suitcaseEmpty : .closetEmpty
            return StyleRequestCheck(issues: [issue], piecesInSource: 0, usablePieces: 0)
        }
        let usable = Eligibility.eligible(
            inSource, members: members, tracksLaundry: preferences.tracksLaundry, on: now)

        var issues: [StyleRequestIssue] = []
        if usable.count < Self.minimumPieces {
            issues.append(.tooFewToStyle(usable: usable.count, total: inSource.count))
        } else if draft.source.isSuitcase && usable.count < Self.fullResultPieces {
            issues.append(.fewPieces(usable: usable.count))
        }
        if let startID = draft.startingPieceID {
            if let start = garmentsByID[startID] {
                let reasons = Eligibility.reasons(
                    for: start, members: members, tracksLaundry: preferences.tracksLaundry, on: now)
                if !reasons.isEmpty { issues.append(.startingPieceUnusable(reasons)) }
            } else {
                issues.append(.startingPieceMissing)
            }
        }
        if draft.occasion == .other {
            do {
                _ = try NameRules.occasionNote(draft.occasionNote)
            } catch {
                issues.append(.occasionNoteInvalid(error))
            }
        }
        if let color = draft.color, color.strength == .required, !usable.contains(where: { color.fits($0) }) {
            issues.append(.requiredColorUnavailable(color))
        }
        return StyleRequestCheck(issues: issues, piecesInSource: inSource.count, usablePieces: usable.count)
    }

    // MARK: Building

    /// The request to send, or `cannotStyle` with what stops it.
    ///
    /// - Parameter weather: today's weather, `nil` when it couldn't be read. It's only kept when
    ///   she chose Use today's weather, so an indoors request carries no weather at all.
    public func build(
        _ draft: StyleRequestDraft,
        weather: WeatherSnapshot?,
        id: StyleRequest.ID,
        createdAt: Date
    ) throws(StyleRequestError) -> StyleRequest {
        let check = check(draft)
        guard check.canStyle else { throw .cannotStyle(check.blockingIssues) }
        var requestPreferences = preferences
        requestPreferences.pieceMode = draft.pieceMode
        return StyleRequest(
            id: id,
            source: draft.source,
            occasion: draft.occasion,
            occasionNote: occasionNote(for: draft),
            weatherChoice: draft.weatherChoice,
            weather: draft.weatherChoice == .useToday ? weather : nil,
            comfort: draft.comfort,
            color: draft.color,
            preferences: requestPreferences,
            startingPieceID: draft.startingPieceID,
            createdAt: createdAt
        )
    }

    /// The trimmed note for Other, or `nil` when there are no words or the occasion isn't Other.
    private func occasionNote(for draft: StyleRequestDraft) -> String? {
        guard draft.occasion == .other, let note = try? NameRules.occasionNote(draft.occasionNote), !note.isEmpty
        else { return nil }
        return note
    }
}
