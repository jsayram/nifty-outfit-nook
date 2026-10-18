import Foundation
import Models

/// A generated closet for performance and layout checks: 2,400 garments, 600 looks, 40
/// suitcases and a simulated try-on picture for every third saved look, with every state mixed
/// in at realistic rates.
///
/// Generated from a fixed seed, so every run makes the same closet (for the same `now`). The nine
/// in ten pieces that have a photo take one of the sample wardrobe's, by kind and colour, and the
/// photo's colours, so the same few dozen photos and cutouts are shared by the whole closet and
/// the image loader keeps just the ones on screen.
enum LargeCloset {
    static let garmentCount = 2_400
    static let lookCount = 600
    static let suitcaseCount = 40
    static let seed: UInt64 = 2_026_10_14

    static func make(now: Date, calendar: Calendar) -> FixtureData {
        var random = SeededGenerator(seed: seed)
        let day = { (offset: Int) in calendar.day(offset, from: now) }
        let garments = (0..<garmentCount).map { garment(index: $0, random: &random, day: day) }
        let suitcases = (0..<suitcaseCount).map { suitcase(index: $0, garments: garments, random: &random, day: day) }
        let looks = (0..<lookCount).map { look(index: $0, garments: garments, random: &random, day: day) }
        return FixtureData(
            garments: garments,
            looks: looks,
            suitcases: suitcases,
            profile: DemoCloset.profile,
            weather: FixtureWeather.rainyDay(at: now),
            pictures: pictures(of: looks)
        )
    }

    /// A simulated picture of every third saved look, made the day it was saved. No random
    /// numbers, so the garments, suitcases and looks stay exactly as before pictures existed.
    static func pictures(of looks: [Look]) -> [TryOnPicture] {
        looks.filter(\.isSaved).enumerated().compactMap { index, look in
            guard index.isMultiple(of: 3) else { return nil }
            return TryOnPicture(
                id: TryOnPicture.ID("p-large-\(look.id.rawValue)"), of: look, image: .simulated,
                createdAt: look.savedDate)
        }
    }

    // MARK: Garments

    private static let categoryWeights: [(GarmentCategory, Int)] = [
        (.top, 30), (.bottom, 20), (.dress, 10), (.layer, 15), (.shoes, 15), (.bag, 6), (.accessory, 4),
    ]

    private static let nouns: [GarmentCategory: [String]] = [
        .top: ["blouse", "tee", "sweater", "knit top", "shirt", "tank"],
        .bottom: ["trousers", "jeans", "skirt", "shorts", "culottes"],
        .dress: ["midi dress", "wrap dress", "shirt dress", "slip dress"],
        .layer: ["cardigan", "blazer", "jacket", "coat", "vest"],
        .shoes: ["flats", "loafers", "sneakers", "boots", "heels", "sandals"],
        .bag: ["tote", "crossbody bag", "clutch", "backpack"],
        .accessory: ["scarf", "belt", "hat"],
    ]

    private static let adjectives = [
        "Soft", "Everyday", "Favourite", "Cozy", "Smart", "Light", "Classic", "Linen", "Cotton", "Wool", "Silky",
        "Striped", "Plain", "Cropped", "Long",
    ]

    static func garment(index: Int, random: inout SeededGenerator, day: (Int) -> Date) -> Garment {
        let category = random.weighted(categoryWeights)
        let colors = random.distinctElements(from: ColorName.allCases, count: random.int(in: 1...2))
        let noun = random.element(of: nouns[category] ?? ["piece"])
        let adjective = random.element(of: adjectives)
        let name = "\(adjective) \(colors[0].rawValue) \(noun)"
        let addedDaysAgo = random.int(in: 0...900)

        var garment = Garment(
            id: Garment.ID(String(format: "g-large-%04d", index)),
            name: name,
            category: category,
            colors: colors,
            fit: random.chance(0.85) ? random.element(of: GarmentFit.allCases) : nil,
            dressiness: random.element(of: Dressiness.allCases),
            warmth: random.element(of: Warmth.allCases),
            seasons: Set(random.distinctElements(from: Season.allCases, count: random.int(in: 1...4))),
            occasions: Set(random.distinctElements(from: Occasion.allCases, count: random.int(in: 1...3))),
            brand: random.chance(0.3) ? "Brand \(random.int(in: 1...60))" : nil,
            photo: random.chance(0.9) ? .sample("large-\(category.rawValue)") : .noPhoto,
            addedAt: day(-addedDaysAgo)
        )
        // A real photo of the same kind of piece (the same colour when there is one), picked from
        // the index and not from the generator, so nothing else about the closet changes. The
        // piece takes the photo's colours and is named for them, so searching "green" finds green
        // pieces. A piece with no photo keeps its random colours, which its drawing shows.
        if garment.photo != .noPhoto,
            let entry = SampleWardrobe.pick(category: category, noun: noun, color: colors.first, index: index)
        {
            garment = SampleWardrobe.dressed(garment, asset: entry.asset)
            garment.colors = entry.colors
            garment.name = "\(adjective) \(entry.colors[0].rawValue) \(noun)"
        }

        let roll = random.unit()
        if roll < 0.03 {
            garment.ownership = .wishlisted
        } else if roll < 0.07 {
            garment.ownership = .noLongerOwned
        } else if roll < 0.10 {
            garment.ownership = .purchased(random.element(of: ArrivalState.allCases))
        }
        if random.chance(0.03) { garment.isArchived = true }
        if random.chance(0.02) { garment.deletedAt = day(-random.int(in: 0...29)) }
        if random.chance(0.12) { garment.laundry = .dirty }
        if random.chance(0.02) { garment.availability = .unavailable(until: day(random.int(in: 1...14))) }
        let wears = random.int(in: 0...4)
        let wornDaysAgo = Set((0..<wears).map { _ in random.int(in: 0...min(120, addedDaysAgo)) })
        garment.wornOn = wornDaysAgo.sorted(by: >).map { day(-$0) }
        return garment
    }

    // MARK: Suitcases

    private static let places = [
        "Beach house", "Mom's", "Weekend away", "Ski trip", "Work trip", "Gym", "Jose's house", "Lake cabin",
    ]

    static func suitcase(
        index: Int,
        garments: [Garment],
        random: inout SeededGenerator,
        day: (Int) -> Date
    ) -> Suitcase {
        let place = places[index % places.count]
        let round = index / places.count
        let members = (0..<random.int(in: 15...150)).map { _ in random.element(of: garments).id }
        return Suitcase(
            id: Suitcase.ID(String(format: "s-large-%02d", index)),
            name: round == 0 ? place : "\(place) \(round + 1)",
            icon: random.element(of: SuitcaseIcon.allCases),
            garmentIDs: Set(members),
            lastUsedAt: random.chance(0.7) ? day(-random.int(in: 0...200)) : nil,
            isArchived: index % 13 == 12,
            createdAt: day(-random.int(in: 0...400))
        )
    }

    // MARK: Looks

    static func look(index: Int, garments: [Garment], random: inout SeededGenerator, day: (Int) -> Date) -> Look {
        let pick = { (category: GarmentCategory, random: inout SeededGenerator) -> Garment.ID in
            // Probe until a garment of the category turns up. Every category is common, so this ends fast.
            while true {
                let garment = random.element(of: garments)
                if garment.category == category { return garment.id }
            }
        }
        var ids: [Garment.ID] = []
        if random.chance(0.5) { ids.append(pick(.layer, &random)) }
        if random.chance(0.2) {
            ids.append(pick(.dress, &random))
        } else {
            ids.append(pick(.top, &random))
            ids.append(pick(.bottom, &random))
        }
        ids.append(pick(.shoes, &random))

        let id = Look.ID(String(format: "o-large-%04d", index))
        let version = random.chance(0.85) ? random.element(of: LookVersion.allCases) : nil
        let isSaved = random.chance(0.8)
        let occasion = random.element(of: Occasion.allCases)
        let wears = random.chance(0.3) ? random.int(in: 1...2) : 0
        // In this order, so the generator gives the same set as before `savedAt` existed.
        let wornOn = Set((0..<wears).map { _ in random.int(in: 0...60) }).sorted(by: >).map { day(-$0) }
        let created = day(-random.int(in: 0...300))
        return Look(
            id: id,
            resultID: version == nil ? nil : StyleResult.ID("r-large-\(index)"),
            version: version,
            pieces: ids.map { garmentID in
                LookPiece(id: LookPiece.ID("\(id)-\(garmentID)"), content: .garment(garmentID), isSameAsSimple: true)
            },
            name: isSaved ? "\(occasion.rawValue.capitalized) look \(index + 1)" : nil,
            occasion: occasion,
            isSaved: isSaved,
            savedAt: isSaved ? created : nil,
            wornOn: wornOn,
            createdAt: created
        )
    }
}

/// SplitMix64: a small, fast generator that gives the same numbers for the same seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// A number in `range`. Uses its own arithmetic so the result doesn't depend on how the
    /// standard library picks random integers.
    mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// A number from 0 up to, not including, 1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    mutating func element<T>(of array: [T]) -> T {
        array[int(in: 0...(array.count - 1))]
    }

    mutating func distinctElements<T>(from array: [T], count: Int) -> [T] {
        var pool = array
        var picked: [T] = []
        for _ in 0..<min(count, pool.count) {
            picked.append(pool.remove(at: int(in: 0...(pool.count - 1))))
        }
        return picked
    }

    mutating func weighted<T>(_ choices: [(T, Int)]) -> T {
        var roll = int(in: 0...(choices.reduce(0) { $0 + $1.1 } - 1))
        for (choice, weight) in choices {
            if roll < weight { return choice }
            roll -= weight
        }
        return choices[choices.count - 1].0
    }
}
