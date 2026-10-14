import Foundation
import Models

/// A stand-in stylist for Stage A. Deterministic: the same context always gives the same result.
///
/// It uses plain matching on stored facts only (occasion tags, season, warmth against the
/// temperature, fit against comfort, colour), and no real fit or styling rules. Those stay in
/// the private backend (SECURITY_STANDARD.md §3 and §7). Its looks are good enough to build and
/// test screens with, not to judge taste.
public struct MockStylist: Stylist {
    public enum Mode: Hashable, Sendable {
        /// Styles normally.
        case normal
        /// Throws this error every time.
        case failing(StylistError)
        /// Returns Simple and Dressed up only, as a partial result.
        case partial
    }

    public var mode: Mode
    public var latency: Duration

    public init(mode: Mode = .normal, latency: Duration = .zero) {
        self.mode = mode
        self.latency = latency
    }

    public func style(_ context: StylingContext) async throws(StylistError) -> StyleOutcome {
        if latency > .zero {
            do {
                try await Task.sleep(for: latency)
            } catch {
                throw .cancelled
            }
        }
        if Task.isCancelled { throw .cancelled }
        switch mode {
        case .failing(let error):
            throw error
        case .normal:
            return MockStyling(context: context).outcome()
        case .partial:
            return Self.partial(from: MockStyling(context: context).outcome())
        }
    }

    /// Cuts a complete result down to two versions.
    static func partial(from outcome: StyleOutcome) -> StyleOutcome {
        guard case .complete(var result) = outcome else { return outcome }
        result.versions.removeAll { $0.version == .somethingNew }
        return .partial(result, missing: [MissingVersion(version: .somethingNew, reason: .noOtherOwnedPiece)])
    }
}

/// The mock stylist's matching, for one context.
struct MockStyling {
    let context: StylingContext
    private let request: StyleRequest
    private var pools: [GarmentCategory: [Garment]] = [:]
    private let start: Garment?
    private let season: Season?
    private let band: TemperatureBand?
    private let comfortFit: GarmentFit?

    /// How many alternatives to keep per piece: enough for three rounds of Show 3 more.
    static let alternateCount = 9
    /// How many tops and bottoms to pair when looking for a base outfit.
    static let pairingDepth = 6

    init(context: StylingContext) {
        self.context = context
        request = context.request
        let weather = context.request.weatherToUse
        season = weather.map { Season.of($0.observedAt, calendar: context.calendar) }
        band = weather?.band
        comfortFit = context.effectiveComfort?.matchingFit
        start = context.request.startingPieceID.flatMap { id in context.eligibleGarments.first { $0.id == id } }
        let grouped = Dictionary(grouping: context.eligibleGarments, by: \.category)
        pools = grouped.mapValues(ranked)
    }

    // MARK: Matching

    /// Counts the stored facts that match the request.
    func score(_ garment: Garment) -> Int {
        var score = 0
        if garment.occasions.contains(request.occasion) { score += 2 }
        if let season, garment.seasons.contains(season) { score += 1 }
        if let band, band.suitableWarmth.contains(garment.warmth) { score += 1 }
        if let comfortFit, garment.fit == comfortFit { score += 1 }
        if let color = request.color, garment.colors.contains(color) { score += 2 }
        return score
    }

    /// Best match first; ties go to the less dressy piece, then by name and ID.
    func ranked(_ garments: [Garment]) -> [Garment] {
        garments.map { ($0, score($0)) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.dressiness != rhs.0.dressiness { return lhs.0.dressiness < rhs.0.dressiness }
                if lhs.0.name != rhs.0.name { return lhs.0.name < rhs.0.name }
                return lhs.0.id < rhs.0.id
            }
            .map(\.0)
    }

    private func pool(_ category: GarmentCategory) -> [Garment] {
        pools[category] ?? []
    }

    /// Rain, snow or a cool day calls for a layer, when the weather is in use.
    private var wantsLayer: Bool {
        guard let weather = request.weatherToUse else { return false }
        return weather.condition == .rain || weather.condition == .snow || [.cold, .cool].contains(weather.band)
    }

    // MARK: Outcome

    func outcome() -> StyleOutcome {
        let shoes = start?.category == .shoes ? start : pool(.shoes).first
        let mains = mainCombinations()
        guard let shoes, !mains.isEmpty else {
            return .insufficient(InsufficientWardrobe(source: request.source, missing: missingCategories(shoes)))
        }

        var notes: [ResultNote] = []
        let fresh = mains.first { context.recentCombinations[Set($0.map(\.id))] == nil }
        let main = fresh ?? mains[0]
        if fresh == nil, let worn = context.recentCombinations[Set(main.map(\.id))] {
            notes.append(.wornRecently(lastWorn: worn))
        }

        var basePieces = main + [shoes]
        if start?.category == .layer, let start {
            basePieces.append(start)
        } else if wantsLayer, let layer = pool(.layer).first {
            basePieces.append(layer)
        }
        if start?.category == .bag, let start {
            basePieces.append(start)
        } else if let bag = pool(.bag).first, bag.occasions.contains(request.occasion) {
            basePieces.append(bag)
        }
        if start?.category == .accessory, let start { basePieces.append(start) }
        basePieces.sort { $0.category < $1.category }

        let resultID = StyleResult.ID("r-\(request.id)")
        let simple = makeLook(.simple, resultID: resultID, garments: basePieces, simpleIDs: [])
        let simpleIDs = Set(basePieces.map(\.id))
        var versions = [simple]
        var missing: [MissingVersion] = []

        // Dressed up: swap one piece for the dressiest one she owns that's dressier than it.
        let dressedUp = swapped(basePieces, preferring: [.top, .dress, .shoes, .layer, .bottom, .bag]) { current in
            let dressier = pool(current.category)
                .filter { $0.dressiness > current.dressiness && !simpleIDs.contains($0.id) }
            let dressiest = dressier.map(\.dressiness).max()
            return dressier.first { $0.dressiness == dressiest }
        }
        if let dressedUp {
            versions.append(makeLook(.dressedUp, resultID: resultID, garments: dressedUp.pieces, simpleIDs: simpleIDs))
        } else {
            missing.append(MissingVersion(version: .dressedUp, reason: .noDressierPiece))
        }

        // Something new: Simple plus one idea, or another owned version when ideas aren't allowed.
        if request.allowsNewPieceIdea, basePieces.count < ResultCheck.pieceRange.upperBound {
            let newPiece = idea(for: basePieces)
            versions.append(
                makeLook(.somethingNew, resultID: resultID, garments: basePieces, simpleIDs: simpleIDs, idea: newPiece))
        } else {
            if request.source.isSuitcase && request.preferences.pieceMode == .mineAndOneIdea {
                notes.append(.noNewPieceInSuitcase)
            }
            let used = simpleIDs.union(dressedUp.map { [$0.replacement] } ?? [])
            let other = swapped(basePieces, preferring: [.shoes, .bottom, .top, .layer, .bag]) { current in
                pool(current.category).first { !used.contains($0.id) }
            }
            if let other {
                versions.append(
                    makeLook(.somethingNew, resultID: resultID, garments: other.pieces, simpleIDs: simpleIDs))
            } else {
                missing.append(MissingVersion(version: .somethingNew, reason: .noOtherOwnedPiece))
            }
        }

        if request.weatherChoice == .useToday && request.weather == nil { notes.append(.weatherUnavailable) }
        let result = StyleResult(
            id: resultID,
            requestID: request.id,
            versions: versions,
            alternates: alternates(for: basePieces),
            notes: notes,
            createdAt: context.now
        )
        return missing.isEmpty ? .complete(result) : .partial(result, missing: missing)
    }

    /// Candidate main pieces (a dress, or a top and a bottom), best first. A starting top,
    /// bottom or dress is in every candidate.
    func mainCombinations() -> [[Garment]] {
        let tops = Array(pool(.top).prefix(Self.pairingDepth))
        let bottoms = Array(pool(.bottom).prefix(Self.pairingDepth))
        var combinations: [[Garment]]
        switch start?.category {
        case .dress: combinations = [start].compactMap(\.self).map { [$0] }
        case .top: combinations = pairs(tops: [start].compactMap(\.self), bottoms: bottoms)
        case .bottom: combinations = pairs(tops: tops, bottoms: [start].compactMap(\.self))
        default: combinations = pool(.dress).map { [$0] } + pairs(tops: tops, bottoms: bottoms)
        }
        let average = { (pieces: [Garment]) in Double(pieces.map(score).reduce(0, +)) / Double(pieces.count) }
        return combinations.sorted { lhs, rhs in
            let left = average(lhs)
            let right = average(rhs)
            if left != right { return left > right }
            return lhs.map(\.id.rawValue).joined(separator: "+") < rhs.map(\.id.rawValue).joined(separator: "+")
        }
    }

    private func pairs(tops: [Garment], bottoms: [Garment]) -> [[Garment]] {
        tops.flatMap { top in bottoms.map { bottom in [top, bottom] } }
    }

    /// What's missing when no outfit can be made.
    func missingCategories(_ shoes: Garment?) -> [GarmentCategory] {
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
        if shoes == nil { missing.append(.shoes) }
        return missing
    }

    /// Replaces the first piece, in category order, for which `replacement` finds a garment.
    /// The starting piece is never replaced.
    private func swapped(
        _ pieces: [Garment],
        preferring order: [GarmentCategory],
        replacement: (Garment) -> Garment?
    ) -> (pieces: [Garment], replacement: Garment.ID)? {
        for category in order {
            for (index, current) in pieces.enumerated() where current.category == category && current.id != start?.id {
                if let new = replacement(current) {
                    var swapped = pieces
                    swapped[index] = new
                    return (swapped, new.id)
                }
            }
        }
        return nil
    }

    /// An idea piece in a category the outfit doesn't have yet.
    private func idea(for pieces: [Garment]) -> PieceIdea {
        let present = Set(pieces.map(\.category))
        let ideas = [
            PieceIdea(name: "Cropped cardigan", category: .layer, colors: [.cream]),
            PieceIdea(name: "Small structured bag", category: .bag, colors: [.tan]),
            PieceIdea(name: "Thin belt", category: .accessory, colors: [.brown]),
        ]
        return ideas.first { !present.contains($0.category) } ?? ideas[ideas.count - 1]
    }

    private func alternates(for pieces: [Garment]) -> [PieceAlternates] {
        let used = Set(pieces.map(\.id))
        return pieces.map { piece in
            PieceAlternates(
                category: piece.category,
                garmentIDs: pool(piece.category).filter { !used.contains($0.id) }.prefix(Self.alternateCount).map(\.id)
            )
        }
    }

    private func makeLook(
        _ version: LookVersion,
        resultID: StyleResult.ID,
        garments: [Garment],
        simpleIDs: Set<Garment.ID>,
        idea: PieceIdea? = nil
    ) -> Look {
        let lookID = Look.ID("\(resultID)-\(version.rawValue)")
        var pieces = garments.map { garment in
            LookPiece(
                id: LookPiece.ID("\(lookID)-\(garment.id)"),
                content: .garment(garment.id),
                isSameAsSimple: version == .simple || simpleIDs.contains(garment.id)
            )
        }
        if let idea {
            pieces.append(LookPiece(id: LookPiece.ID("\(lookID)-idea"), content: .idea(idea)))
        }
        return Look(
            id: lookID,
            resultID: resultID,
            version: version,
            pieces: pieces,
            occasion: request.occasion,
            source: request.source,
            createdAt: context.now
        )
    }
}
