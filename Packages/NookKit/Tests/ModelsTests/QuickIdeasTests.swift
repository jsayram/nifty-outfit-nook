import Foundation
import Models
import NookTestSupport
import Synchronization
import Testing

/// Quick ideas (Phase 28), the rule-based stylist on the phone. Property checks over hundreds of
/// generated closets and requests, then a few worked examples.
struct QuickIdeasTests {
    /// A why writer that says what it was given, so tests can read it back.
    static let stylist = QuickIdeasStylist { why in "\(why.version.rawValue) \(why.change)" }

    // MARK: Properties

    /// Every result passes `ResultCheck`, uses only her own pieces from the context, has no piece
    /// twice and no two versions alike, says it was made on the phone, gives every version a why
    /// line, and comes out the same twice.
    @Test func everyResultIsValidAndOnlyHerPieces() async throws {
        var results = 0
        for seed in 0..<400 {
            var random = SeededRandom(seed: UInt64(seed))
            let context = Generated.context(&random, weatherNeutral: false)
            let outcome = try await Self.stylist.style(context)
            #expect(try await Self.stylist.style(context) == outcome, "seed \(seed): not deterministic")
            guard let result = outcome.result else {
                guard case .insufficient(let wardrobe) = outcome else { continue }
                #expect(!wardrobe.missing.isEmpty, "seed \(seed)")
                continue
            }
            results += 1
            #expect(ResultCheck.problems(in: result, for: context).isEmpty, "seed \(seed)")
            #expect(result.madeBy == .rules)
            let hers = Set(context.eligibleGarments.map(\.id))
            var seen: Set<[LookPiece.Content]> = []
            for look in result.versions {
                #expect(look.garmentIDs.allSatisfy(hers.contains), "seed \(seed): a piece that isn't hers")
                #expect(Set(look.garmentIDs).count == look.garmentIDs.count, "seed \(seed): a piece twice")
                #expect(seen.insert(look.pieces.map(\.content)).inserted, "seed \(seed): two versions alike")
                #expect(look.why?.isEmpty == false, "seed \(seed): no why line")
            }
        }
        #expect(results > 300)
    }

    /// With today's weather in use, every top, bottom, dress and layer suits the band whenever she
    /// owns one of that kind that does; a cold, cool or wet day adds a layer when she has one that
    /// suits, and a hot day never does.
    @Test func everyLookMatchesTheWeatherBand() async throws {
        var checked = 0
        for seed in 0..<400 {
            var random = SeededRandom(seed: UInt64(seed) &+ 10_000)
            let context = Generated.context(&random, weatherNeutral: false)
            guard let weather = context.request.weatherToUse, let result = try await Self.stylist.style(context).result
            else { continue }
            checked += 1
            let band = weather.band
            let byID = Dictionary(uniqueKeysWithValues: context.eligibleGarments.map { ($0.id, $0) })
            let startID = context.request.startingPieceID
            for look in result.versions {
                for piece in look.garmentIDs.compactMap({ byID[$0] }) where piece.id != startID {
                    guard [.top, .bottom, .dress, .layer].contains(piece.category) else { continue }
                    let suitable = context.eligibleGarments.contains {
                        $0.category == piece.category && band.suitableWarmth.contains($0.warmth)
                    }
                    #expect(
                        !suitable || band.suitableWarmth.contains(piece.warmth),
                        "seed \(seed): \(piece.category) of \(piece.warmth) warmth on a \(band) day")
                }
            }
            let simple = try #require(result.simple).garmentIDs.compactMap { byID[$0] }
            let hasLayer = simple.contains { $0.category == .layer }
            let wet = weather.condition == .rain || weather.condition == .snow
            let startIsLayer = byID[startID ?? ""]?.category == .layer
            if band == .hot && !startIsLayer {
                #expect(!hasLayer, "seed \(seed): a layer on a hot day")
            } else if band == .cold || band == .cool || wet,
                context.eligibleGarments.contains(where: {
                    $0.category == .layer && band.suitableWarmth.contains($0.warmth)
                })
            {
                #expect(hasLayer, "seed \(seed): no layer on a \(band) day")
            }
        }
        #expect(checked > 150)
    }

    /// Simple never repeats an outfit she wore inside her repeat window, or one already shown for
    /// this request, while another one is possible; when it has to, the result says so.
    @Test func noRepeatsWhileAnotherOutfitIsPossible() async throws {
        var checked = 0
        for seed in 0..<400 {
            var random = SeededRandom(seed: UInt64(seed) &+ 20_000)
            let context = Generated.context(&random, weatherNeutral: true)
            guard let result = try await Self.stylist.style(context).result, let simple = result.simple else {
                continue
            }
            checked += 1
            let categories = Dictionary(uniqueKeysWithValues: context.eligibleGarments.map { ($0.id, $0.category) })
            let main = WearRules.mainPieces(of: simple, categories: categories)
            let possible = Generated.possibleMains(context)
            let unshown = possible.subtracting(context.shownCombinations)
            if !unshown.isEmpty {
                #expect(!context.shownCombinations.contains(main), "seed \(seed): shown again")
            }
            let fresh = (unshown.isEmpty ? possible : unshown).filter { context.recentCombinations[$0] == nil }
            if !fresh.isEmpty {
                #expect(context.recentCombinations[main] == nil, "seed \(seed): a recent outfit again")
            }
            if context.recentCombinations[main] != nil {
                #expect(result.notes.contains { if case .wornRecently = $0 { true } else { false } }, "seed \(seed)")
            }
        }
        #expect(checked > 300)
    }

    // MARK: Examples

    /// Formality follows the occasion: the dressy top for date night, the casual one for brunch.
    @Test func dressinessFollowsTheOccasion() async throws {
        let closet = [
            piece("tee", .top, .white, dressiness: .casual, occasions: [.brunch, .dateNight]),
            piece("silk", .top, .cream, dressiness: .dressy, occasions: [.brunch, .dateNight]),
            piece("jeans", .bottom, .denim, dressiness: .smart, occasions: [.brunch, .dateNight]),
            piece("flats", .shoes, .black, dressiness: .smart, occasions: [.brunch, .dateNight]),
        ]
        let date = try await simple(closet, occasion: .dateNight)
        #expect(date.contains("silk"))
        let brunch = try await simple(closet, occasion: .brunch)
        #expect(brunch.contains("tee"))
    }

    /// Neutrals and one colour beat two colours.
    @Test func coloursGoTogether() async throws {
        let closet = [
            piece("red-top", .top, .red),
            piece("green-skirt", .bottom, .green),
            piece("navy-trousers", .bottom, .navy),
            piece("black-flats", .shoes, .black),
        ]
        #expect(try await simple(closet).contains("navy-trousers"))
    }

    /// A cold, wet day: the warm pieces, a warm layer, and no sandals.
    @Test func aColdWetDayGetsWarmPiecesALayerAndNoSandals() async throws {
        let closet = [
            piece("tank", .top, .white, warmth: .light),
            piece("sweater", .top, .gray, warmth: .warm),
            piece("wool-trousers", .bottom, .navy, warmth: .warm),
            piece("linen-shorts", .bottom, .beige, warmth: .light),
            piece("trench", .layer, .tan, warmth: .warm),
            piece("sandals", .shoes, .tan, subKind: .sandals),
            piece("boots", .shoes, .brown, subKind: .boots),
        ]
        let weather = WeatherSnapshot(condition: .rain, temperatureCelsius: 4, observedAt: TestTime.now)
        let pieces = try await simple(closet, weather: weather)
        #expect(Set(pieces) == ["sweater", "wool-trousers", "trench", "boots"])
    }

    /// A hot day: light pieces and no layer, even though she owns one.
    @Test func aHotDayGetsLightPiecesAndNoLayer() async throws {
        let closet = [
            piece("tank", .top, .white, warmth: .light),
            piece("sweater", .top, .gray, warmth: .warm),
            piece("shorts", .bottom, .beige, warmth: .light),
            piece("cardigan", .layer, .cream, warmth: .light),
            piece("sandals", .shoes, .tan, subKind: .sandals),
        ]
        let weather = WeatherSnapshot(condition: .sun, temperatureCelsius: 31, observedAt: TestTime.now)
        #expect(Set(try await simple(closet, weather: weather)) == ["tank", "shorts", "sandals"])
    }

    /// Variety: a piece worn yesterday gives way to an equal one she hasn't worn lately.
    @Test func aPieceWornYesterdayGivesWay() async throws {
        let closet = [
            piece("a-top", .top, .white, wornOn: [TestTime.day(-1)]),
            piece("b-top", .top, .white),
            piece("trousers", .bottom, .black),
            piece("flats", .shoes, .black),
        ]
        #expect(try await simple(closet).contains("b-top"))
    }

    /// The why lines come from the facts: the occasion, the palette, the weather and the change.
    @Test func theWhyLinesSayWhatTheLookIsAbout() async throws {
        let lock = WhyLog()
        let stylist = QuickIdeasStylist { why in
            lock.add(why)
            return "why"
        }
        let closet = [
            piece("sweater", .top, .gray, dressiness: .smart, warmth: .warm),
            piece("blouse", .top, .cream, dressiness: .dressy, warmth: .warm),
            piece("trousers", .bottom, .navy, warmth: .warm),
            piece("coat", .layer, .red, warmth: .warm),
            piece("loafers", .shoes, .brown),
        ]
        let weather = WeatherSnapshot(condition: .snow, temperatureCelsius: -2, observedAt: TestTime.now)
        _ = try await stylist.style(context(closet, weather: weather))
        let told = lock.all
        #expect(told.count == 3)
        let simple = try #require(told.first { $0.version == .simple })
        #expect(simple.weather == .outdoors(.cold, wet: true))
        #expect(simple.addsLayer)
        #expect(simple.palette == .neutralsAnd(.red))
        #expect(told.first { $0.version == .dressedUp }?.change == .dressier(.top))
        if case .idea = told.first(where: { $0.version == .somethingNew })?.change {
        } else {
            Issue.record("Something new should add an idea")
        }
    }

    /// No shoes, or nothing to wear with the starting piece: insufficient, saying what's missing.
    @Test func anOutfitThatCantBeMadeSaysWhatsMissing() async throws {
        let noShoes = [piece("top", .top, .white), piece("skirt", .bottom, .black)]
        guard case .insufficient(let wardrobe) = try await Self.stylist.style(context(noShoes)) else {
            Issue.record("Expected insufficient")
            return
        }
        #expect(wardrobe.missing == [.shoes])
    }

    /// A 150-piece closet, the most the stylist is sent, styles quickly on the phone.
    @Test func aLargeClosetStylesQuickly() async throws {
        var random = SeededRandom(seed: 7)
        var closet: [Garment] = []
        for index in 0..<150 {
            let category: GarmentCategory = [.top, .top, .bottom, .bottom, .dress, .layer, .shoes, .bag][index % 8]
            closet.append(Generated.garment("g\(index)", category, &random))
        }
        let big = context(closet)
        let elapsed = try await SpeedCheck.fastest(of: 3) {
            _ = try await Self.stylist.style(big)
        }
        #expect(elapsed < SpeedCheck.limit(.milliseconds(500)), "took \(elapsed)")
    }

    // MARK: Helpers

    private func piece(
        _ id: String, _ category: GarmentCategory, _ color: ColorName, subKind: GarmentSubKind? = nil,
        dressiness: Dressiness = .smart, warmth: Warmth = .medium, occasions: Set<Occasion> = [.office],
        wornOn: [Date] = []
    ) -> Garment {
        Garment(
            id: Garment.ID(id), name: id, category: category, subKind: subKind, colors: [color], dressiness: dressiness,
            warmth: warmth, occasions: occasions, wornOn: wornOn, addedAt: TestTime.day(-30))
    }

    private func context(
        _ closet: [Garment], occasion: Occasion = .office, weather: WeatherSnapshot? = nil
    ) -> StylingContext {
        let request = StyleRequest(
            id: "req-q", occasion: occasion, weatherChoice: weather == nil ? .indoors : .useToday, weather: weather,
            createdAt: TestTime.now)
        return StylingContext(
            request: request, eligibleGarments: closet, now: TestTime.now, calendar: TestTime.calendar)
    }

    private func simple(
        _ closet: [Garment], occasion: Occasion = .office, weather: WeatherSnapshot? = nil
    ) async throws -> [String] {
        let outcome = try await Self.stylist.style(context(closet, occasion: occasion, weather: weather))
        return try #require(outcome.result?.simple).garmentIDs.map(\.rawValue)
    }
}

/// Collects why facts from the writer, which may run on any thread.
final class WhyLog: Sendable {
    private let items = Mutex<[QuickIdeasWhy]>([])
    func add(_ why: QuickIdeasWhy) { items.withLock { $0.append(why) } }
    var all: [QuickIdeasWhy] { items.withLock { $0 } }
}

/// A small, seeded random number generator (SplitMix64), so every generated case can be re-run.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Random closets and requests for the property checks.
enum Generated {
    static func garment(_ id: String, _ category: GarmentCategory, _ random: inout SeededRandom) -> Garment {
        let kinds = GarmentSubKind.choices(for: category)
        let worn: [Date] = Bool.random(using: &random) ? [TestTime.day(-Int.random(in: 0...20, using: &random))] : []
        return Garment(
            id: Garment.ID(id), name: id, category: category, subKind: kinds.randomElement(using: &random),
            colors: [ColorName.allCases.randomElement(using: &random) ?? .black],
            fit: GarmentFit.allCases.randomElement(using: &random),
            dressiness: Dressiness.allCases.randomElement(using: &random) ?? .smart,
            warmth: Warmth.allCases.randomElement(using: &random) ?? .medium,
            occasions: Set(Occasion.allCases.filter { _ in Bool.random(using: &random) }), wornOn: worn,
            addedAt: TestTime.day(-60))
    }

    /// - Parameter weatherNeutral: indoors or ignored weather and no colour wish, so every
    ///   combination is possible and the repeat check can count them.
    static func context(_ random: inout SeededRandom, weatherNeutral: Bool) -> StylingContext {
        let counts: [GarmentCategory: ClosedRange<Int>] = [
            .top: 0...7, .bottom: 0...6, .dress: 0...3, .layer: 0...4, .shoes: 0...4, .bag: 0...3, .accessory: 0...2,
        ]
        var closet: [Garment] = []
        for category in GarmentCategory.allCases {
            for index in 0..<Int.random(in: counts[category] ?? 0...1, using: &random) {
                closet.append(garment("\(category.rawValue)-\(index)", category, &random))
            }
        }
        let start = Int.random(in: 0..<4, using: &random) == 0 ? closet.randomElement(using: &random) : nil
        let weatherChoice: WeatherChoice =
            weatherNeutral
            ? (Bool.random(using: &random) ? .indoors : .ignore)
            : [.useToday, .useToday, .useToday, .indoors].randomElement(using: &random) ?? .useToday
        let weather = WeatherSnapshot(
            condition: WeatherCondition.allCases.randomElement(using: &random) ?? .sun,
            temperatureCelsius: Double(Int.random(in: -5...35, using: &random)), observedAt: TestTime.now)
        let color: ColorWish? =
            !weatherNeutral && Int.random(in: 0..<4, using: &random) == 0
            ? ColorWish(
                ColorName.allCases.randomElement(using: &random) ?? .red,
                strength: Bool.random(using: &random) ? .required : .preferred)
            : nil
        let source: WardrobeSource = Int.random(in: 0..<5, using: &random) == 0 ? .suitcase("trip") : .mainCloset
        let request = StyleRequest(
            id: "req-gen", source: source, occasion: Occasion.allCases.randomElement(using: &random) ?? .office,
            weatherChoice: weatherChoice, weather: weather, color: color,
            preferences: Preferences(pieceMode: Bool.random(using: &random) ? .mineAndOneIdea : .onlyMine),
            startingPieceID: start?.id, createdAt: TestTime.now)
        var context = StylingContext(
            request: request, eligibleGarments: closet, now: TestTime.now, calendar: TestTime.calendar)
        // Some of the possible outfits were worn lately, and some were already shown.
        for main in possibleMains(context) {
            if Int.random(in: 0..<3, using: &random) == 0 { context.recentCombinations[main] = TestTime.day(-2) }
            if Int.random(in: 0..<5, using: &random) == 0 { context.shownCombinations.insert(main) }
        }
        return context
    }

    /// Every main-piece combination around the starting piece, when there are shoes to wear.
    static func possibleMains(_ context: StylingContext) -> Set<Set<Garment.ID>> {
        let pieces = context.eligibleGarments
        let start = pieces.first { $0.id == context.request.startingPieceID }
        let of = { (category: GarmentCategory) in pieces.filter { $0.category == category } }
        guard !of(.shoes).isEmpty else { return [] }
        let mains: [[Garment]]
        switch start?.category {
        case .dress: mains = [[start].compactMap(\.self)]
        case .top: mains = of(.bottom).map { [start].compactMap(\.self) + [$0] }
        case .bottom: mains = of(.top).map { [$0] + [start].compactMap(\.self) }
        default: mains = of(.dress).map { [$0] } + of(.top).flatMap { top in of(.bottom).map { [top, $0] } }
        }
        return Set(mains.map { Set($0.map(\.id)) })
    }
}
