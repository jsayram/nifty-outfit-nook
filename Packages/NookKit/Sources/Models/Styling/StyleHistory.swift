import Foundation

/// What a styling request asked for, in allowlisted structured terms (PRD 11.11): enough to tell
/// whether an earlier result answers today's request, and nothing she typed. Kept with the looks
/// the cloud stylist made, so "From your history" (FR-58) can be checked before a paid request.
///
/// Data tier: **Personal** (like the look it belongs to).
public struct StyleIntent: Codable, Hashable, Sendable {
    /// How the weather shaped the request: a temperature band and whether it was wet, indoors, or
    /// ignored. Never a reading, a place or a time.
    public enum WeatherFit: Codable, Hashable, Sendable {
        case outdoors(TemperatureBand, wet: Bool)
        case indoors
        case ignored
    }

    public var source: WardrobeSource
    public var occasion: Occasion
    public var startingPieceID: Garment.ID?
    public var color: ColorWish?
    public var ideaAllowed: Bool
    public var weather: WeatherFit

    public init(
        source: WardrobeSource, occasion: Occasion, startingPieceID: Garment.ID?, color: ColorWish?,
        ideaAllowed: Bool, weather: WeatherFit
    ) {
        self.source = source
        self.occasion = occasion
        self.startingPieceID = startingPieceID
        self.color = color
        self.ideaAllowed = ideaAllowed
        self.weather = weather
    }

    /// The intent of a request, or `nil` when part of it can't be represented this way, so no
    /// earlier result can count as an exact answer: words she typed for an Other occasion, a
    /// comfort for today (never kept in history, LR-18), or today's weather that couldn't be read.
    public init?(_ request: StyleRequest) {
        if request.occasionNote != nil || request.comfort != nil { return nil }
        let weather: WeatherFit
        switch request.weatherChoice {
        case .indoors: weather = .indoors
        case .ignore: weather = .ignored
        case .useToday:
            guard let today = request.weather else { return nil }
            weather = .outdoors(today.band, wet: today.condition == .rain || today.condition == .snow)
        }
        self.init(
            source: request.source, occasion: request.occasion, startingPieceID: request.startingPieceID,
            color: request.color, ideaAllowed: request.allowsNewPieceIdea, weather: weather)
    }
}

/// "From your history" (FR-58, PRD 11.11): before a paid request, look for an earlier stylist
/// result in her own looks that answers the same request and that she can still wear today. All
/// on the phone; nothing is sent and nothing is used.
public enum StyleHistory {
    /// The newest earlier result for this exact intent whose every piece is eligible today (in the
    /// source, in her closet, not away or in the wash) and whose main pieces weren't shown already
    /// for this request. Its looks keep their IDs, so saving one saves that very look.
    public static func match(for context: StylingContext, in looks: [Look]) -> StyleResult? {
        guard let intent = StyleIntent(context.request) else { return nil }
        let eligible = Set(context.eligibleGarments.map(\.id))
        let categories = Dictionary(
            context.eligibleGarments.map { ($0.id, $0.category) }, uniquingKeysWith: { first, _ in first })
        let candidates = Dictionary(
            grouping: looks.filter { $0.intent == intent && $0.resultID != nil && $0.version != nil },
            by: { $0.resultID! })
        let results = candidates.values
            .compactMap { versions -> StyleResult? in
                let ordered = LookVersion.allCases.compactMap { v in versions.first { $0.version == v } }
                guard let simple = ordered.first, simple.version == .simple,
                    ordered.allSatisfy({ $0.garmentIDs.allSatisfy(eligible.contains) }),
                    !context.shownCombinations.contains(WearRules.mainPieces(of: simple, categories: categories))
                else { return nil }
                if let start = context.request.startingPieceID,
                    !ordered.allSatisfy({ $0.garmentIDs.contains(start) })
                {
                    return nil
                }
                return StyleResult(
                    id: simple.resultID!, requestID: context.request.id, versions: ordered, notes: [.fromHistory],
                    createdAt: simple.createdAt)
            }
        return results.max { $0.createdAt < $1.createdAt }
    }
}
