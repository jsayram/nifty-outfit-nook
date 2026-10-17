import Foundation
import Models

// The pieces beyond the demo closet's 21 (`-fixtures demo:wardrobe=full`), and the try-on previews.

extension SampleWardrobe {
    /// One extra piece: every kind of clothing, bag and accessory the app has a category for.
    struct Extra: Sendable {
        let asset: String
        let name: String
        let category: GarmentCategory
        let colors: [ColorName]
        var colorNote: String?
        var fit: GarmentFit?
        var dressiness: Dressiness = .smart
        var warmth: Warmth = .medium
        var seasons: Set<Season> = Set(Season.allCases)
        var occasions: Set<Occasion> = []
        /// Days ago she last wore it, if she has.
        var wornDaysAgo: [Int] = []
        let words: Set<String>

        /// The garment's ID: the asset's name with `g-` for `x-`.
        var id: Garment.ID { Garment.ID("g-" + asset.dropFirst(2)) }

        func garment(day: (Int) -> Date, index: Int) -> Garment {
            let garment = Garment(
                id: id, name: name, category: category, colors: colors, colorNote: colorNote, fit: fit,
                dressiness: dressiness, warmth: warmth, seasons: seasons, occasions: occasions,
                wornOn: wornDaysAgo.sorted(by: >).map { day(-$0) }, addedAt: day(-(14 + index * 9)))
            return SampleWardrobe.dressed(garment, asset: asset)
        }
    }

    /// The 30 extras as garments. Four more generated items (a bra set, pajamas, a swimsuit and a
    /// sports set) have no category in the app, so they aren't here.
    static func extraGarments(day: (Int) -> Date) -> [Garment] {
        Extra.all.enumerated().map { $1.garment(day: day, index: $0) }
    }
}

extension SampleWardrobe.Extra {
    static let all: [SampleWardrobe.Extra] = [
        .init(
            asset: "x-white-shirt", name: "White button-up shirt", category: .top, colors: [.white],
            fit: .regular, dressiness: .smart, warmth: .light, seasons: [.spring, .summer, .fall],
            occasions: [.office, .brunch, .casual], wornDaysAgo: [8], words: ["shirt", "blouse"]),
        .init(
            asset: "x-striped-tee", name: "Navy striped tee", category: .top, colors: [.navy, .white],
            fit: .regular, dressiness: .casual, warmth: .medium, occasions: [.casual, .brunch], wornDaysAgo: [3],
            words: ["tee", "shirt"]),
        .init(
            asset: "x-turtleneck", name: "Black turtleneck", category: .top, colors: [.black], fit: .fitted,
            dressiness: .smart, warmth: .warm, seasons: [.fall, .winter], occasions: [.office, .dateNight, .event],
            wornDaysAgo: [30], words: ["sweater", "knit top"]),
        .init(
            asset: "x-silk-cami", name: "Champagne silk cami", category: .top, colors: [.beige],
            colorNote: "Champagne", fit: .fitted, dressiness: .dressy, warmth: .light,
            seasons: [.spring, .summer, .fall], occasions: [.dateNight, .event], words: ["tank", "blouse"]),
        .init(
            asset: "x-black-jeans", name: "Black straight jeans", category: .bottom, colors: [.black],
            fit: .regular, dressiness: .casual, occasions: [.casual, .concert, .dateNight], wornDaysAgo: [6, 40],
            words: ["jeans", "trousers"]),
        .init(
            asset: "x-linen-pants", name: "Cream linen pants", category: .bottom, colors: [.cream], fit: .relaxed,
            dressiness: .smart, warmth: .light, seasons: [.spring, .summer], occasions: [.brunch, .casual, .office],
            words: ["trousers", "culottes"]),
        .init(
            asset: "x-denim-shorts", name: "Light denim shorts", category: .bottom, colors: [.denim],
            colorNote: "Light wash", fit: .regular, dressiness: .casual, warmth: .light, seasons: [.spring, .summer],
            occasions: [.casual], wornDaysAgo: [120], words: ["shorts"]),
        .init(
            asset: "x-plaid-skirt", name: "Red plaid mini skirt", category: .bottom, colors: [.red, .green],
            fit: .fitted, dressiness: .casual, warmth: .medium, seasons: [.fall, .winter],
            occasions: [.casual, .concert], words: ["skirt"]),
        .init(
            asset: "x-tennis-skirt", name: "White tennis skirt", category: .bottom, colors: [.white], fit: .fitted,
            dressiness: .casual, warmth: .light, seasons: [.spring, .summer], occasions: [.casual],
            words: ["skirt", "shorts"]),
        .init(
            asset: "x-black-dress", name: "Little black dress", category: .dress, colors: [.black], fit: .fitted,
            dressiness: .dressy, warmth: .light, occasions: [.dateNight, .event], wornDaysAgo: [50],
            words: ["slip dress", "midi dress"]),
        .init(
            asset: "x-linen-sundress", name: "White linen sundress", category: .dress, colors: [.white],
            fit: .regular, dressiness: .smart, warmth: .light, seasons: [.spring, .summer],
            occasions: [.brunch, .casual, .dateNight], words: ["midi dress", "shirt dress"]),
        .init(
            asset: "x-red-wrap", name: "Red wrap dress", category: .dress, colors: [.red], fit: .regular,
            dressiness: .dressy, warmth: .medium, seasons: [.spring, .fall], occasions: [.dateNight, .event, .brunch],
            words: ["wrap dress", "shirt dress"]),
        .init(
            asset: "x-denim-jacket", name: "Denim jacket", category: .layer, colors: [.denim], fit: .regular,
            dressiness: .casual, warmth: .medium, seasons: [.spring, .fall], occasions: [.casual, .concert],
            wornDaysAgo: [15], words: ["jacket"]),
        .init(
            asset: "x-gray-hoodie", name: "Gray zip hoodie", category: .layer, colors: [.gray], fit: .relaxed,
            dressiness: .casual, warmth: .warm, seasons: [.spring, .fall, .winter], occasions: [.casual],
            wornDaysAgo: [2], words: ["jacket", "cardigan", "vest"]),
        .init(
            asset: "x-puffer", name: "Black puffer jacket", category: .layer, colors: [.black], fit: .relaxed,
            dressiness: .casual, warmth: .warm, seasons: [.winter], occasions: [.casual],
            words: ["jacket", "coat", "vest"]),
        .init(
            asset: "x-wool-coat", name: "Black wool coat", category: .layer, colors: [.black], fit: .regular,
            dressiness: .dressy, warmth: .warm, seasons: [.fall, .winter], occasions: [.office, .event, .dateNight],
            words: ["coat", "blazer"]),
        .init(
            asset: "x-ballet-flats", name: "Black ballet flats", category: .shoes, colors: [.black],
            dressiness: .smart, warmth: .light, occasions: [.office, .brunch, .dateNight], wornDaysAgo: [9],
            words: ["flats"]),
        .init(
            asset: "x-ankle-boots", name: "Brown suede ankle boots", category: .shoes, colors: [.brown],
            colorNote: "Chocolate suede", dressiness: .smart, warmth: .warm, seasons: [.fall, .winter, .spring],
            occasions: [.casual, .office, .dateNight], words: ["boots"]),
        .init(
            asset: "x-knee-boots", name: "Black knee boots", category: .shoes, colors: [.black], dressiness: .smart,
            warmth: .warm, seasons: [.fall, .winter], occasions: [.office, .dateNight, .event], words: ["boots"]),
        .init(
            asset: "x-sandals", name: "Tan strappy sandals", category: .shoes, colors: [.tan], dressiness: .casual,
            warmth: .light, seasons: [.spring, .summer], occasions: [.casual, .brunch], words: ["sandals"]),
        .init(
            asset: "x-black-tote", name: "Black canvas tote", category: .bag, colors: [.black],
            dressiness: .casual, occasions: [.office, .casual], wornDaysAgo: [4], words: ["tote", "backpack"]),
        .init(
            asset: "x-straw-bag", name: "Straw tote bag", category: .bag, colors: [.tan], colorNote: "Natural straw",
            dressiness: .casual, warmth: .light, seasons: [.spring, .summer], occasions: [.casual, .brunch],
            words: ["tote"]),
        .init(
            asset: "x-clutch", name: "Gold evening clutch", category: .bag, colors: [.yellow],
            colorNote: "Gold mesh", dressiness: .dressy, occasions: [.dateNight, .event], words: ["clutch"]),
        .init(
            asset: "x-mini-backpack", name: "Tan mini backpack", category: .bag, colors: [.tan],
            dressiness: .casual, occasions: [.casual, .concert], wornDaysAgo: [25],
            words: ["backpack", "crossbody bag"]),
        .init(
            asset: "x-silk-scarf", name: "Navy paisley silk scarf", category: .accessory, colors: [.navy, .white],
            dressiness: .smart, occasions: [.office, .brunch, .event], words: ["scarf"]),
        .init(
            asset: "x-beanie", name: "Cream knit beanie", category: .accessory, colors: [.cream],
            dressiness: .casual, warmth: .warm, seasons: [.fall, .winter], occasions: [.casual], words: ["hat"]),
        .init(
            asset: "x-belt", name: "Brown leather belt", category: .accessory, colors: [.brown], dressiness: .smart,
            occasions: [.office, .casual], wornDaysAgo: [5], words: ["belt"]),
        .init(
            asset: "x-sunglasses", name: "Tortoise sunglasses", category: .accessory, colors: [.brown],
            colorNote: "Tortoiseshell", dressiness: .casual, warmth: .light, seasons: [.spring, .summer],
            occasions: [.casual, .brunch], words: []),
        .init(
            asset: "x-hoops", name: "Gold hoop earrings", category: .accessory, colors: [.yellow],
            colorNote: "Gold", dressiness: .smart, occasions: [.dateNight, .event, .brunch], words: []),
        .init(
            asset: "x-necklace", name: "Gold pendant necklace", category: .accessory, colors: [.yellow],
            colorNote: "Gold", dressiness: .smart, occasions: [.dateNight, .event, .office], words: []),
    ]
}

// MARK: Try-on previews

extension SampleWardrobe {
    /// The looks and pictures are dated 3 to 5 months back, older than the demo's own, so the
    /// newest looks, Home's shelf and the first pictures stay as they were.
    ///
    /// One preview of her wearing a look (`Resources/SampleWardrobe/tryon`), the look it belongs
    /// to and the pieces it shows. Four use only demo pieces. Two use pieces only the full
    /// wardrobe has, so they're seeded there.
    struct TryOnPreview: Sendable {
        let name: String
        let lookID: Look.ID
        let lookName: String
        let occasion: Occasion
        let pieces: [Garment.ID]
        let needsFullWardrobe: Bool
        let lookCreatedDaysAgo: Int
        let pictureCreatedDaysAgo: Int

        var pictureID: TryOnPicture.ID { TryOnPicture.ID("p-\(name)") }
        var photo: PhotoReference { SampleWardrobe.preview(name) }
    }

    static let previews: [TryOnPreview] = [
        TryOnPreview(
            name: "office", lookID: "o-office-lace", lookName: "Office navy and lace", occasion: .office,
            pieces: ["g-gray-blazer", "g-lace-top", "g-navy-trousers", "g-nude-flats"], needsFullWardrobe: false,
            lookCreatedDaysAgo: 96, pictureCreatedDaysAgo: 93),
        TryOnPreview(
            name: "casual", lookID: "o-casual-jeans", lookName: "Casual jeans and tee", occasion: .casual,
            pieces: ["g-black-tee", "g-wide-jeans", "g-white-sneakers", "g-burgundy-bag"], needsFullWardrobe: false,
            lookCreatedDaysAgo: 106, pictureCreatedDaysAgo: 103),
        TryOnPreview(
            name: "date", lookID: "o-date-crop", lookName: "Date night in a cream crop", occasion: .dateNight,
            pieces: ["g-cream-crop", "g-black-skirt", "g-black-heels"], needsFullWardrobe: false,
            lookCreatedDaysAgo: 116, pictureCreatedDaysAgo: 113),
        TryOnPreview(
            name: "weekend", lookID: "o-weekend-olive", lookName: "Weekend olive and cream", occasion: .casual,
            pieces: ["g-cream-sweater", "g-olive-trousers", "g-tan-loafers"], needsFullWardrobe: false,
            lookCreatedDaysAgo: 126, pictureCreatedDaysAgo: 123),
        TryOnPreview(
            name: "sundress", lookID: "o-sundress", lookName: "Sundress and sneakers", occasion: .brunch,
            pieces: ["g-blue-dress", "g-white-sneakers", "g-straw-bag"], needsFullWardrobe: true,
            lookCreatedDaysAgo: 136, pictureCreatedDaysAgo: 133),
        TryOnPreview(
            name: "cool-weather", lookID: "o-cool-weather", lookName: "Cool-weather trench", occasion: .casual,
            pieces: ["g-camel-trench", "g-black-tee", "g-black-jeans", "g-ankle-boots"], needsFullWardrobe: true,
            lookCreatedDaysAgo: 146, pictureCreatedDaysAgo: 143),
    ]

    /// The looks for these previews, saved, in the order of `previews`.
    static func previewLooks(full: Bool, day: (Int) -> Date) -> [Look] {
        previews.filter { full || !$0.needsFullWardrobe }.map { preview in
            DemoCloset.look(
                preview.lookID, name: preview.lookName, version: nil, occasion: preview.occasion,
                pieces: preview.pieces, createdAt: day(-preview.lookCreatedDaysAgo))
        }
    }

    /// The pictures: each preview worn by her, linked to its look. They're still labelled
    /// Simulated, like every try-on picture.
    static func previewPictures(looks: [Look], day: (Int) -> Date) -> [TryOnPicture] {
        let byID = Dictionary(looks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return previews.compactMap { preview in
            guard let look = byID[preview.lookID] else { return nil }
            return TryOnPicture(
                id: preview.pictureID, of: look, image: .generated(preview.photo),
                createdAt: day(-preview.pictureCreatedDaysAgo))
        }
    }

    /// The preview of her wearing exactly these pieces, if there is one. Only whole garments
    /// count: a look with a piece idea is a different look.
    public static func previewPhoto(for look: Look) -> PhotoReference? {
        var ids: Set<Garment.ID> = []
        for piece in look.pieces {
            guard case .garment(let id) = piece.content else { return nil }
            ids.insert(id)
        }
        return previews.first { Set($0.pieces) == ids }?.photo
    }
}
