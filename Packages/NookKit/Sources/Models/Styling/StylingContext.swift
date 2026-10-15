import Foundation

/// Everything a stylist gets for one request: the request, the eligible pieces from the chosen
/// source, and the main-piece combinations worn inside the repeat window.
///
/// The app builds it on the phone, so the stylist never sees ineligible or out-of-source pieces
/// (PRD §8.1 "bounded snapshot of eligible items"). It holds no profile name, suitcase name or
/// photo.
public struct StylingContext: Hashable, Sendable {
    public var request: StyleRequest
    /// Pieces the stylist may use, sorted by ID so every run sees the same order.
    public var eligibleGarments: [Garment]
    /// Her usual fit, used when the request has no comfort for today (LR-18).
    public var usualFit: Comfort?
    /// Main-piece combinations worn inside the repeat window, with the last day each was worn.
    public var recentCombinations: [Set<Garment.ID>: Date]
    /// Main-piece combinations already shown for this request. Try a different outfit asks for a
    /// new base, so the stylist starts from something else when it can (LR-05a.4).
    public var shownCombinations: Set<Set<Garment.ID>>
    /// When the request is styled. Results and looks are stamped with it.
    public var now: Date
    public var calendar: Calendar

    public init(
        request: StyleRequest,
        eligibleGarments: [Garment],
        usualFit: Comfort? = nil,
        recentCombinations: [Set<Garment.ID>: Date] = [:],
        shownCombinations: Set<Set<Garment.ID>> = [],
        now: Date,
        calendar: Calendar
    ) {
        self.request = request
        self.eligibleGarments = eligibleGarments.sorted { $0.id < $1.id }
        self.usualFit = usualFit
        self.recentCombinations = recentCombinations
        self.shownCombinations = shownCombinations
        self.now = now
        self.calendar = calendar
    }

    /// Builds the context from everything in the stores.
    ///
    /// Throws when the suitcase is missing or archived, or the starting piece can't be used.
    /// - Parameter shown: main-piece combinations already shown for this request, for Try a
    ///   different outfit.
    public static func make(
        request: StyleRequest,
        garments: [Garment],
        suitcases: [Suitcase],
        looks: [Look],
        usualFit: Comfort?,
        shown: Set<Set<Garment.ID>> = [],
        now: Date,
        calendar: Calendar
    ) throws(StylingContextError) -> StylingContext {
        var members: Set<Garment.ID>?
        if let suitcaseID = request.source.suitcaseID {
            guard let suitcase = suitcases.first(where: { $0.id == suitcaseID }) else {
                throw .suitcaseNotFound
            }
            guard !suitcase.isArchived else { throw .suitcaseArchived }
            members = suitcase.garmentIDs
        }
        let tracksLaundry = request.preferences.tracksLaundry
        if let startID = request.startingPieceID {
            guard let start = garments.first(where: { $0.id == startID }) else { throw .startingPieceNotFound }
            let reasons = Eligibility.reasons(for: start, members: members, tracksLaundry: tracksLaundry, on: now)
            guard reasons.isEmpty else { throw .startingPieceNotEligible(reasons) }
        }
        let eligible = Eligibility.eligible(garments, members: members, tracksLaundry: tracksLaundry, on: now)
        let categories = Dictionary(garments.map { ($0.id, $0.category) }, uniquingKeysWith: { first, _ in first })
        let recent = WearRules.recentCombinations(
            in: looks,
            categories: categories,
            window: request.preferences.repeatWindow,
            now: now,
            calendar: calendar
        )
        return StylingContext(
            request: request,
            eligibleGarments: eligible,
            usualFit: usualFit,
            recentCombinations: recent,
            shownCombinations: shown,
            now: now,
            calendar: calendar
        )
    }

    /// Today's comfort, or her usual fit when she didn't pick one.
    public var effectiveComfort: Comfort? {
        request.comfort ?? usualFit
    }
}

/// Why a styling context couldn't be built.
public enum StylingContextError: Error, Hashable, Sendable, Codable {
    case suitcaseNotFound
    case suitcaseArchived
    case startingPieceNotFound
    case startingPieceNotEligible([IneligibilityReason])
}
