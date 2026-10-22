import Foundation

/// Quick ideas' matching for one context (see `QuickIdeasStylist`).
///
/// Simple is the best-scoring outfit (a dress, or a top and a bottom, with shoes) she hasn't been
/// shown for this request and hasn't worn inside her repeat window, when there is one; a layer is
/// added for a cold, cool or wet day and never on a hot one; a bag joins when it's tagged for the
/// occasion. Dressed up swaps in one dressier piece, and Something new adds one idea or swaps in
/// another of her pieces. Every piece comes from `context.eligibleGarments`, so only her own,
/// usable pieces from the chosen source are ever used.
struct QuickIdeas {
    let context: StylingContext
    private let request: StyleRequest
    private let start: Garment?
    private let facts: Facts
    /// Eligible pieces by kind, best match first.
    private let pools: [GarmentCategory: [Garment]]
    /// Each eligible piece's score, worked out once.
    private let scores: [Garment.ID: Int]

    /// How many alternatives to keep per piece: enough for three rounds of Show 3 more.
    static let alternateCount = 9
    /// How many of the best shoes to try with each main piece.
    static let shoeDepth = 6

    init(context: StylingContext) {
        self.context = context
        request = context.request
        let facts = Facts(context: context)
        self.facts = facts
        start = request.startingPieceID.flatMap { id in context.eligibleGarments.first { $0.id == id } }
        let scores = Dictionary(
            context.eligibleGarments.map { ($0.id, facts.score($0)) }, uniquingKeysWith: { first, _ in first })
        self.scores = scores
        // The weather is a firm rule: a top, bottom, dress or layer that doesn't suit today's band
        // is used only when she has nothing of that kind that does.
        pools = Dictionary(grouping: context.eligibleGarments, by: \.category).mapValues { garments in
            let suiting = garments.filter { facts.suitsWeather($0) }
            return (suiting.isEmpty ? garments : suiting).sorted { lhs, rhs in
                let left = scores[lhs.id] ?? 0
                let right = scores[rhs.id] ?? 0
                return left != right ? left > right : lhs.id < rhs.id
            }
        }
    }

    private func score(_ garment: Garment) -> Int {
        scores[garment.id] ?? facts.score(garment)
    }

    private func pool(_ category: GarmentCategory) -> [Garment] {
        pools[category] ?? []
    }

    // MARK: Outcome

    func outcome(why writeWhy: QuickIdeasStylist.WhyWriter) -> StyleOutcome {
        let candidates = outfits()
        guard !candidates.isEmpty else {
            return .insufficient(InsufficientWardrobe(source: request.source, missing: missingCategories()))
        }
        var notes: [ResultNote] = []
        let (main, mainNotes) = pick(from: candidates)
        notes += mainNotes

        var base = main.pieces
        let layer: Garment? =
            if start?.category == .layer { start } else if facts.wantsLayer { best(of: pool(.layer), with: base) } else
            { nil }
        if let layer { base.append(layer) }
        let bag: Garment? =
            if start?.category == .bag {
                start
            } else {
                best(
                    of: pool(.bag).filter { request.occasion != .other && $0.occasions.contains(request.occasion) },
                    with: base)
            }
        if let bag { base.append(bag) }
        if start?.category == .accessory, let start { base.append(start) }
        base.sort { $0.category < $1.category }

        let resultID = StyleResult.ID("r-\(request.id)")
        let simpleIDs = Set(base.map(\.id))
        let addsLayer = layer != nil && start?.category != .layer
        func why(_ version: LookVersion, _ pieces: [Garment], _ change: QuickIdeasWhy.Change) -> String {
            writeWhy(
                QuickIdeasWhy(
                    version: version, occasion: request.occasion, weather: facts.whyWeather, addsLayer: addsLayer,
                    palette: OutfitColors.palette(pieces), change: change))
        }
        var versions = [
            makeLook(.simple, resultID: resultID, garments: base, simpleIDs: [], why: why(.simple, base, .none))
        ]
        var missing: [MissingVersion] = []

        // Dressed up: one dressier piece she owns, kind by kind.
        let dressedUp = swapped(base, order: [.top, .dress, .shoes, .layer, .bottom, .bag]) { current in
            pool(current.category).filter {
                $0.dressiness > current.dressiness && !simpleIDs.contains($0.id)
                    && facts.suitsWeather($0, replacing: current)
            }
            .max { lhs, rhs in
                (lhs.dressiness, value(lhs, in: base, replacing: current), rhs.id)
                    < (rhs.dressiness, value(rhs, in: base, replacing: current), lhs.id)
            }
        }
        if let dressedUp {
            versions.append(
                makeLook(
                    .dressedUp, resultID: resultID, garments: dressedUp.pieces, simpleIDs: simpleIDs,
                    why: why(.dressedUp, dressedUp.pieces, .dressier(dressedUp.replacement.category))))
        } else {
            missing.append(MissingVersion(version: .dressedUp, reason: .noDressierPiece))
        }

        // Something new: Simple plus one idea, or another of her pieces when ideas aren't allowed.
        if request.allowsNewPieceIdea, base.count < ResultCheck.pieceRange.upperBound {
            let newPiece = idea(for: base)
            versions.append(
                makeLook(
                    .somethingNew, resultID: resultID, garments: base, simpleIDs: simpleIDs, idea: newPiece,
                    why: why(.somethingNew, base, .idea(newPiece))))
        } else {
            if request.source.isSuitcase && request.preferences.pieceMode == .mineAndOneIdea {
                notes.append(.noNewPieceInSuitcase)
            }
            let used = simpleIDs.union(dressedUp.map { [$0.replacement.id] } ?? [])
            let other = swapped(base, order: [.shoes, .bottom, .top, .layer, .bag]) { current in
                pool(current.category).filter { !used.contains($0.id) && facts.suitsWeather($0, replacing: current) }
                    .max { lhs, rhs in
                        (value(lhs, in: base, replacing: current), rhs.id) < (
                            value(rhs, in: base, replacing: current), lhs.id
                        )
                    }
            }
            if let other {
                versions.append(
                    makeLook(
                        .somethingNew, resultID: resultID, garments: other.pieces, simpleIDs: simpleIDs,
                        why: why(.somethingNew, other.pieces, .another(other.replacement.category))))
            } else {
                missing.append(MissingVersion(version: .somethingNew, reason: .noOtherOwnedPiece))
            }
        }

        if request.weatherChoice == .useToday && request.weather == nil { notes.append(.weatherUnavailable) }
        if let color = request.color, color.strength == .required, !base.contains(where: color.fits) {
            notes.append(.requiredColorNotMet(color.family))
        }
        let result = StyleResult(
            id: resultID, requestID: request.id, versions: versions, alternates: alternates(for: base), notes: notes,
            createdAt: context.now, madeBy: .rules)
        return missing.isEmpty ? .complete(result) : .partial(result, missing: missing)
    }

    // MARK: The base outfit

    /// A main piece (a dress, or a top and a bottom) with shoes, and its score.
    struct Outfit {
        var pieces: [Garment]
        var score: Int
        var main: Set<Garment.ID>
        var key: String
    }

    /// Every outfit the source can make around the starting piece, best first.
    func outfits() -> [Outfit] {
        let mains: [[Garment]]
        switch start?.category {
        case .dress: mains = [start].compactMap(\.self).map { [$0] }
        case .top: mains = pool(.bottom).compactMap { bottom in start.map { [$0, bottom] } }
        case .bottom: mains = pool(.top).compactMap { top in start.map { [top, $0] } }
        default: mains = pool(.dress).map { [$0] } + pool(.top).flatMap { top in pool(.bottom).map { [top, $0] } }
        }
        let shoes = start?.category == .shoes ? [start].compactMap(\.self) : Array(pool(.shoes).prefix(Self.shoeDepth))
        var outfits: [Outfit] = []
        for main in mains {
            let mainScore = main.map(score).reduce(0, +)
            let mainIDs = Set(main.map(\.id))
            for shoe in shoes {
                let pieces = main + [shoe]
                outfits.append(
                    Outfit(
                        pieces: pieces, score: mainScore + score(shoe) + OutfitColors.weightedHarmony(pieces),
                        main: mainIDs, key: pieces.map(\.id.rawValue).joined(separator: "+")))
            }
        }
        // A required colour: only outfits that bring it in, when any can.
        if let color = request.color, color.strength == .required {
            let bringing = outfits.filter { $0.pieces.contains(where: color.fits) }
            if !bringing.isEmpty { outfits = bringing }
        }
        return outfits.sorted { $0.score != $1.score ? $0.score > $1.score : $0.key < $1.key }
    }

    /// The best outfit not shown yet for this request (Try a different outfit), and not worn
    /// inside her repeat window, when there is one. Says so when it has to repeat.
    private func pick(from outfits: [Outfit]) -> (Outfit, [ResultNote]) {
        var notes: [ResultNote] = []
        let unshown = outfits.filter { !context.shownCombinations.contains($0.main) }
        if unshown.isEmpty && !context.shownCombinations.isEmpty { notes.append(.noOtherOutfit) }
        let candidates = unshown.isEmpty ? outfits : unshown
        if let fresh = candidates.first(where: { context.recentCombinations[$0.main] == nil }) {
            return (fresh, notes)
        }
        let main = candidates[0]
        if let worn = context.recentCombinations[main.main] { notes.append(.wornRecently(lastWorn: worn)) }
        return (main, notes)
    }

    /// The best of `garments` to add to `pieces`: its own score and how the colours sit together.
    private func best(of garments: [Garment], with pieces: [Garment]) -> Garment? {
        garments.max { lhs, rhs in
            (score(lhs) + OutfitColors.weightedHarmony(pieces + [lhs]), rhs.id)
                < (score(rhs) + OutfitColors.weightedHarmony(pieces + [rhs]), lhs.id)
        }
    }

    /// How good `garment` is in place of `current`.
    private func value(_ garment: Garment, in pieces: [Garment], replacing current: Garment) -> Int {
        score(garment) + OutfitColors.weightedHarmony(pieces.map { $0.id == current.id ? garment : $0 })
    }

    /// Replaces the first piece, in `order`, for which `replacement` finds a garment. The
    /// starting piece is never replaced.
    private func swapped(
        _ pieces: [Garment], order: [GarmentCategory], replacement: (Garment) -> Garment?
    ) -> (pieces: [Garment], replacement: Garment)? {
        for category in order {
            for (index, current) in pieces.enumerated() where current.category == category && current.id != start?.id {
                if let new = replacement(current) {
                    var swapped = pieces
                    swapped[index] = new
                    return (swapped, new)
                }
            }
        }
        return nil
    }

    /// What's missing when no outfit can be made.
    func missingCategories() -> [GarmentCategory] {
        var missing: [GarmentCategory] = []
        switch start?.category {
        case .dress: break
        case .top: if pool(.bottom).isEmpty { missing.append(.bottom) }
        case .bottom: if pool(.top).isEmpty { missing.append(.top) }
        default:
            if pool(.dress).isEmpty {
                if pool(.top).isEmpty { missing.append(.top) }
                if pool(.bottom).isEmpty { missing.append(.bottom) }
            }
        }
        if start?.category != .shoes && pool(.shoes).isEmpty { missing.append(.shoes) }
        return missing
    }

    /// One idea piece in a kind the outfit doesn't have yet, in a neutral that goes with anything.
    private func idea(for pieces: [Garment]) -> PieceIdea {
        let present = Set(pieces.map(\.category))
        if !present.contains(.layer) && facts.band != .hot {
            return PieceIdea(name: "Cropped cardigan", category: .layer, colors: [.cream])
        }
        if !present.contains(.bag) {
            return PieceIdea(name: "Small structured bag", category: .bag, colors: [.tan])
        }
        return PieceIdea(name: "Thin belt", category: .accessory, colors: [.brown])
    }

    private func alternates(for pieces: [Garment]) -> [PieceAlternates] {
        let used = Set(pieces.map(\.id))
        return pieces.map { piece in
            PieceAlternates(
                category: piece.category,
                garmentIDs: pool(piece.category).filter { !used.contains($0.id) }.prefix(Self.alternateCount).map(\.id))
        }
    }

    private func makeLook(
        _ version: LookVersion, resultID: StyleResult.ID, garments: [Garment], simpleIDs: Set<Garment.ID>,
        idea: PieceIdea? = nil, why: String
    ) -> Look {
        let lookID = Look.ID("\(resultID)-\(version.rawValue)")
        var pieces = garments.map { garment in
            LookPiece(
                id: LookPiece.ID("\(lookID)-\(garment.id)"), content: .garment(garment.id),
                isSameAsSimple: version == .simple || simpleIDs.contains(garment.id))
        }
        if let idea {
            pieces.append(LookPiece(id: LookPiece.ID("\(lookID)-idea"), content: .idea(idea)))
        }
        return Look(
            id: lookID, resultID: resultID, version: version, pieces: pieces, occasion: request.occasion,
            source: request.source, createdAt: context.now, why: why.isEmpty ? nil : why)
    }
}

// MARK: - Facts

extension QuickIdeas {
    /// The request's facts every piece is matched against.
    struct Facts {
        let occasion: Occasion
        let dressiness: Dressiness?
        let weather: WeatherSnapshot?
        let band: TemperatureBand?
        let season: Season?
        let isWet: Bool
        let comfortFit: GarmentFit?
        let color: ColorWish?
        let now: Date
        let calendar: Calendar

        /// Pieces whose warmth has to suit the weather.
        static let warmthKinds: Set<GarmentCategory> = [.top, .bottom, .dress, .layer]
        /// A piece worn this many days ago or less was just worn, so others go first.
        static let justWornDays = 3

        init(context: StylingContext) {
            let request = context.request
            occasion = request.occasion
            dressiness = request.occasion.usualDressiness
            weather = request.weatherToUse
            band = weather?.band
            season = weather.map { Season.of($0.observedAt, calendar: context.calendar) }
            isWet = weather.map { $0.condition == .rain || $0.condition == .snow } ?? false
            comfortFit = context.effectiveComfort?.matchingFit
            color = request.color
            now = context.now
            calendar = context.calendar
        }

        /// A cold, cool or wet day outside calls for a layer; a hot one never does.
        var wantsLayer: Bool {
            guard let band else { return false }
            return band == .cold || band == .cool || (isWet && band != .hot)
        }

        var whyWeather: QuickIdeasWhy.Weather {
            band.map { .outdoors($0, wet: isWet) } ?? .notUsed
        }

        /// How well one piece matches the request, from stored facts only.
        func score(_ garment: Garment) -> Int {
            var score = 0
            if occasion != .other && garment.occasions.contains(occasion) { score += 3 }
            if let dressiness {
                switch abs(garment.dressiness.rawValue - dressiness.rawValue) {
                case 0: score += 2
                case 1: break
                default: score -= 3
                }
            }
            if let band, Self.warmthKinds.contains(garment.category) {
                score += band.suitableWarmth.contains(garment.warmth) ? 2 : -3
            }
            if let season, garment.seasons.contains(season) { score += 1 }
            if let comfortFit, garment.fit == comfortFit { score += 1 }
            if let color, color.fits(garment) { score += color.strength == .required ? 4 : 2 }
            if garment.category == .shoes { score += shoeWeather(garment) }
            if let worn = garment.lastWorn, worn <= now,
                (calendar.dateComponents([.day], from: worn, to: now).day ?? Int.max) <= Self.justWornDays
            {
                score -= 1
            }
            return score
        }

        /// Open shoes stay home on a wet or cold day; boots wait for one.
        private func shoeWeather(_ shoe: Garment) -> Int {
            guard let band else { return 0 }
            switch shoe.subKind {
            case .sandals: return isWet || band == .cold || band == .cool ? -3 : 0
            case .boots: return isWet || band == .cold ? 1 : (band == .hot ? -2 : 0)
            default: return 0
            }
        }

        /// Whether `garment`'s warmth suits today's band. Always true without weather, and for
        /// shoes, bags and accessories.
        func suitsWeather(_ garment: Garment) -> Bool {
            guard let band, Self.warmthKinds.contains(garment.category) else { return true }
            return band.suitableWarmth.contains(garment.warmth)
        }

        /// Whether `garment` can take `current`'s place in today's weather: it suits the band, or
        /// the piece it replaces didn't either.
        func suitsWeather(_ garment: Garment, replacing current: Garment) -> Bool {
            suitsWeather(garment) || !suitsWeather(current)
        }
    }
}

extension Occasion {
    /// How dressy the occasion usually is, for plain matching against a piece's dressiness. `nil`
    /// for Other, whose words aren't read on the phone.
    public var usualDressiness: Dressiness? {
        switch self {
        case .casual, .brunch, .concert: .casual
        case .office: .smart
        case .dateNight, .event: .dressy
        case .other: nil
        }
    }
}

// MARK: - Colours

/// A common palette check: neutrals go with everything, one colour family on top of them works,
/// and more than one colour (or more than one print) is harder to wear. Uses each piece's main
/// colour.
enum OutfitColors {
    enum Role: Hashable {
        case neutral
        case color(Family)
        case print
    }

    /// Colour families: shades of one family count as one colour.
    enum Family: Hashable {
        case red, pink, orange, yellow, green, blue, purple
    }

    static func role(_ color: ColorName) -> Role {
        switch color {
        case .black, .white, .cream, .beige, .tan, .brown, .gray, .navy, .denim: .neutral
        case .red, .brick, .burgundy: .color(.red)
        case .pink: .color(.pink)
        case .orange: .color(.orange)
        case .yellow: .color(.yellow)
        case .green, .olive: .color(.green)
        case .blue: .color(.blue)
        case .purple: .color(.purple)
        case .multicolor: .print
        }
    }

    /// From -4 (clashing) to 3 (neutrals and one colour).
    static func harmony(_ garments: [Garment]) -> Int {
        let roles = garments.compactMap(\.mainColor).map(role)
        let prints = roles.filter { $0 == .print }.count
        let families = Set(
            roles.compactMap { role -> Family? in if case .color(let family) = role { family } else { nil } })
        if prints > 1 { return -4 }
        if prints == 1 { return families.isEmpty ? 1 : -2 }
        switch families.count {
        case 0: return 2
        case 1: return 3
        case 2: return -1
        default: return -4
        }
    }

    /// Harmony weighted against the pieces' own scores.
    static func weightedHarmony(_ garments: [Garment]) -> Int {
        harmony(garments) * 2
    }

    static func palette(_ garments: [Garment]) -> QuickIdeasWhy.Palette {
        let colors = garments.compactMap(\.mainColor)
        let accents = colors.filter { role($0) != .neutral }
        if accents.isEmpty { return .neutrals }
        guard let first = accents.first, accents.allSatisfy({ role($0) == role(first) }), role(first) != .print else {
            return .mixed
        }
        return .neutralsAnd(first)
    }
}
