import Foundation

/// What Swap a piece needs to know about the look and the day, besides the garments.
public struct SwapSituation: Hashable, Sendable {
    /// Where the look's pieces come from. Options come only from here (LR-07.2).
    public var source: WardrobeSource
    /// The suitcase's garment IDs when the source is a suitcase.
    public var members: Set<Garment.ID>?
    public var occasion: Occasion?
    /// The weather the look was made for, if it used any.
    public var weather: WeatherSnapshot?
    /// Today's comfort or her usual fit, as a garment cut.
    public var fit: GarmentFit?
    /// With laundry tracking on, pieces in the wash aren't offered (RD-11).
    public var tracksLaundry: Bool
    /// Main-piece combinations worn inside her repeat window, with the last day each was worn
    /// (`WearRules.recentCombinations`).
    public var recentCombinations: [Set<Garment.ID>: Date]
    public var date: Date
    public var calendar: Calendar

    public init(
        source: WardrobeSource = .mainCloset,
        members: Set<Garment.ID>? = nil,
        occasion: Occasion? = nil,
        weather: WeatherSnapshot? = nil,
        fit: GarmentFit? = nil,
        tracksLaundry: Bool = false,
        recentCombinations: [Set<Garment.ID>: Date] = [:],
        date: Date,
        calendar: Calendar
    ) {
        self.source = source
        self.members = members
        self.occasion = occasion
        self.weather = weather
        self.fit = fit
        self.tracksLaundry = tracksLaundry
        self.recentCombinations = recentCombinations
        self.date = date
        self.calendar = calendar
    }
}

/// The pieces Swap a piece can offer for one piece of a look, in order (LR-07).
public struct SwapOptions: Hashable, Sendable {
    /// The kind of piece being swapped. Options are always the same kind.
    public var category: GarmentCategory
    /// Good matches, best first. These are the ones shown three at a time.
    public var ranked: [Garment.ID]
    /// Pieces that can be worn but may not go with this look, best first. Only See all shows
    /// them, marked "May not match" (LR-07.3).
    public var weaker: [Garment.ID]
    /// Pieces that would make an outfit she wore inside her repeat window (LR-10), with the
    /// last day she wore it. Only See all shows them.
    public var wornRecently: [Garment.ID: Date]

    public init(
        category: GarmentCategory,
        ranked: [Garment.ID] = [],
        weaker: [Garment.ID] = [],
        wornRecently: [Garment.ID: Date] = [:]
    ) {
        self.category = category
        self.ranked = ranked
        self.weaker = weaker
        self.wornRecently = wornRecently
    }

    /// Every piece See all lists: good matches first, then the weaker ones, then those worn
    /// together recently.
    public var all: [Garment.ID] {
        ranked + weaker
            + wornRecently.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map(\.key)
    }

    public var isEmpty: Bool { ranked.isEmpty && weaker.isEmpty && wornRecently.isEmpty }
}

/// Ranks the pieces Swap a piece offers, on the phone, with no request (LR-07.1).
///
/// This is plain matching on stored facts, as the amendment asks: the same kind of piece, the
/// occasion tags, the weather (warmth and season), her fit, how dressy the piece being replaced
/// is, and colour families that sit together. Pieces that can't be worn from this source today
/// are never offered (`Eligibility`). No fit or styling rules live here; better ranking would
/// come from the private backend later.
public enum SwapRanking {
    /// Colour families that go with any other colour: the usual neutrals, with navy, denim and
    /// olive. A plain lookup, like a paint chart's neutrals, not a judgement about a look.
    public static let neutralColors: Set<ColorName> = [
        .black, .white, .cream, .beige, .tan, .brown, .gray, .navy, .denim, .olive,
    ]

    /// True when two pieces' colours sit together: either is unknown or neutral, or they share
    /// a colour family. Multicolour counts as going with anything, since one tag can't say which
    /// colours are in it.
    public static func colorsGo(_ first: [ColorName], with second: [ColorName]) -> Bool {
        guard let a = first.first, let b = second.first else { return true }
        let relaxed = neutralColors.union([.multicolor])
        if relaxed.contains(a) || relaxed.contains(b) { return true }
        return !Set(first).isDisjoint(with: second)
    }

    /// The options for one piece of a look.
    ///
    /// - Parameters:
    ///   - pieceID: the piece being swapped. Its kind decides the options.
    ///   - garments: every garment she has, by ID. Ineligible ones are left out here.
    public static func options(
        for pieceID: LookPiece.ID,
        in look: Look,
        garments: [Garment.ID: Garment],
        situation: SwapSituation
    ) -> SwapOptions? {
        guard let piece = look.pieces.first(where: { $0.id == pieceID }) else { return nil }
        let replaced = piece.garmentID.flatMap { garments[$0] }
        guard let category = replaced?.category ?? piece.idea?.category else { return nil }

        let inLook = Set(look.garmentIDs)
        let others = look.pieces.filter { $0.id != pieceID }.compactMap { other -> (GarmentCategory, [ColorName])? in
            switch other.content {
            case .garment(let id): garments[id].map { ($0.category, $0.colors) }
            case .idea(let idea): (idea.category, idea.colors)
            }
        }
        let otherMain = Set(
            look.pieces.filter { $0.id != pieceID }.compactMap(\.garmentID).filter { id in
                garments[id].map { WearRules.mainCategories.contains($0.category) } ?? false
            })

        var scored: [(garment: Garment, score: Int, isStrong: Bool)] = []
        var wornRecently: [Garment.ID: Date] = [:]
        for garment in garments.values where garment.category == category && !inLook.contains(garment.id) {
            guard
                Eligibility.isEligible(
                    garment, members: situation.members, tracksLaundry: situation.tracksLaundry, on: situation.date)
            else { continue }
            if WearRules.mainCategories.contains(category),
                let worn = situation.recentCombinations[otherMain.union([garment.id])]
            {
                wornRecently[garment.id] = worn
                continue
            }
            let goesWithRest = others.allSatisfy { colorsGo(garment.colors, with: $0.1) }
            let occasionFits = situation.occasion.map(garment.occasions.contains) ?? true
            let warmthFits = situation.weather.map { $0.band.suitableWarmth.contains(garment.warmth) } ?? true
            scored.append(
                (
                    garment, score(garment, replacing: replaced, colorsGo: goesWithRest, situation: situation),
                    goesWithRest && occasionFits && warmthFits
                ))
        }

        let ordered = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            // Ties: the one she wore longest ago (or never) first, then by name and ID.
            let left = lhs.garment.lastWorn ?? .distantPast
            let right = rhs.garment.lastWorn ?? .distantPast
            if left != right { return left < right }
            if lhs.garment.name != rhs.garment.name { return lhs.garment.name < rhs.garment.name }
            return lhs.garment.id < rhs.garment.id
        }
        return SwapOptions(
            category: category,
            ranked: ordered.filter(\.isStrong).map(\.garment.id),
            weaker: ordered.filter { !$0.isStrong }.map(\.garment.id),
            wornRecently: wornRecently
        )
    }

    /// Counts the stored facts that match: occasion 2, colours that sit with the rest 2, and one
    /// each for warmth, season, fit and the replaced piece's dressiness.
    static func score(
        _ garment: Garment,
        replacing replaced: Garment?,
        colorsGo: Bool,
        situation: SwapSituation
    ) -> Int {
        var score = 0
        if let occasion = situation.occasion, garment.occasions.contains(occasion) { score += 2 }
        if colorsGo { score += 2 }
        if let weather = situation.weather {
            if weather.band.suitableWarmth.contains(garment.warmth) { score += 1 }
            if garment.seasons.contains(Season.of(weather.observedAt, calendar: situation.calendar)) { score += 1 }
        }
        if let fit = situation.fit, garment.fit == fit { score += 1 }
        if let replaced, garment.dressiness == replaced.dressiness { score += 1 }
        return score
    }
}
