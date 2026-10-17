import Foundation
import Models

/// The demo closet: the old prototype's 21 garments in the new model, ten looks (nine saved),
/// seven try-on pictures, six suitcases and a profile named Lily. Twenty of the garments have a
/// photo and a cutout from the sample wardrobe (`SampleWardrobe`); the old gray leggings were
/// added by words alone.
///
/// It covers every state a screen needs to show: owned, bought but not arrived, wishlist, no
/// longer owned, Recently deleted, archived, unavailable until a date, dirty (with tracking
/// off, so still styled), text-only pieces, worn recently and long ago, an empty suitcase, an
/// archived suitcase, and a saved Something new look with an idea piece. Brands and sizes are
/// made up. No body measurements are included.
enum DemoCloset {
    // Suitcase IDs, used by tests too.
    static let josesHouse: Suitcase.ID = "s-jose"
    static let weekend: Suitcase.ID = "s-weekend"
    static let springTrip: Suitcase.ID = "s-spring"
    static let gym: Suitcase.ID = "s-gym"
    static let beach: Suitcase.ID = "s-beach"
    static let oldDorm: Suitcase.ID = "s-old-dorm"

    static func make(now: Date, calendar: Calendar) -> FixtureData {
        let day = { (offset: Int) in calendar.day(offset, from: now) }
        let garments = garments(day: day)
        let looks = looks(day: day) + SampleWardrobe.previewLooks(full: false, day: day)
        return FixtureData(
            garments: garments,
            looks: looks,
            suitcases: suitcases(day: day),
            profile: profile,
            weather: FixtureWeather.rainyDay(at: now),
            pictures: pictures(looks: looks, day: day)
        )
    }

    /// Three simulated try-on pictures, as in `saved.html` and `picture.html`: two of the
    /// Interview look (the newer one of the look as it is, the older one of an earlier version
    /// with the cream sweater) and one of Lace date night. Simulated pictures show no person.
    /// Four more show her wearing a look, from the sample wardrobe's previews.
    static func pictures(looks: [Look], day: (Int) -> Date) -> [TryOnPicture] {
        simulatedPictures(looks: looks, day: day) + SampleWardrobe.previewPictures(looks: looks, day: day)
    }

    private static func simulatedPictures(looks: [Look], day: (Int) -> Date) -> [TryOnPicture] {
        let byID = Dictionary(looks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let interview = byID["o-interview"], let lace = byID["o-lace-date"] else { return [] }
        var earlier = CapturedLook(interview)
        earlier.pieces = earlier.pieces.map { piece in
            guard piece.garmentID == "g-pink-blouse" else { return piece }
            return LookPiece(id: "o-interview-g-cream-sweater", content: .garment("g-cream-sweater"))
        }
        return [
            TryOnPicture(id: "p-interview", of: interview, image: .simulated, createdAt: day(-38)),
            TryOnPicture(
                id: "p-interview-earlier", lookID: interview.id, captured: earlier, image: .simulated,
                createdAt: day(-39)),
            TryOnPicture(id: "p-lace", of: lace, image: .simulated, createdAt: day(-72)),
        ]
    }

    static let profile = Profile(
        signName: "Lily",
        preferences: Preferences(),
        usualFit: .relaxed,
        likedColors: [.navy, .pink, .olive, .brick],
        avoidedColors: [.orange],
        fitPieces: [
            FitPiece(
                id: "f-jeans",
                brand: "Example Denim Co.",
                category: .bottom,
                sizeLabel: "S",
                result: .fitsWell,
                garmentID: "g-wide-jeans"
            )
        ]
    )

    /// The garments with their photos and cutouts.
    static func garments(day: (Int) -> Date) -> [Garment] {
        SampleWardrobe.dressedDemo(drawnGarments(day: day))
    }

    /// The garments as the old prototype had them, with sample art names and no cutouts.
    private static func drawnGarments(day: (Int) -> Date) -> [Garment] {
        [
            Garment(
                id: "g-navy-trousers", name: "Navy dress pants", category: .bottom, colors: [.navy], fit: .regular,
                dressiness: .dressy, occasions: [.office, .dateNight, .event], brand: "Demo Brand A",
                photo: .sample("navy-trousers"), wornOn: [day(-200), day(-5)], addedAt: day(-220)
            ),
            Garment(
                id: "g-olive-trousers", name: "Olive trousers", category: .bottom, colors: [.olive],
                colorNote: "Muted olive", fit: .relaxed, occasions: [.office, .casual, .brunch],
                photo: .sample("olive-trousers"), wornOn: [day(-20)], addedAt: day(-90)
            ),
            Garment(
                id: "g-pink-blouse", name: "Cute pink shirt", category: .top, colors: [.pink], colorNote: "Light pink",
                fit: .regular, dressiness: .dressy, warmth: .light,
                occasions: [.office, .dateNight, .brunch, .event], notes: "Bow at the neck",
                photo: .sample("pink-blouse"), wornOn: [day(-5)], addedAt: day(-60)
            ),
            Garment(
                id: "g-lace-top", name: "White lace top", category: .top, colors: [.white], fit: .fitted,
                dressiness: .dressy, warmth: .light, seasons: [.spring, .summer, .fall],
                occasions: [.dateNight, .event, .brunch], photo: .sample("lace-top"), laundry: .dirty,
                wornOn: [day(-70)], addedAt: day(-158)
            ),
            Garment(
                id: "g-navy-cardigan", name: "Navy cardigan", category: .layer, colors: [.navy], fit: .relaxed,
                warmth: .warm, seasons: [.spring, .fall, .winter], occasions: [.office, .casual, .brunch],
                photo: .sample("navy-cardigan"), wornOn: [day(-5)], addedAt: day(-55)
            ),
            Garment(
                id: "g-brown-jacket", name: "Brown leather jacket", category: .layer, colors: [.brown],
                colorNote: "Chocolate brown", fit: .regular, warmth: .warm, seasons: [.spring, .fall, .winter],
                occasions: [.casual, .dateNight, .concert], notes: "Hits at the hip",
                photo: .sample("brown-jacket"), wornOn: [day(-20)], addedAt: day(-50)
            ),
            Garment(
                id: "g-cream-sweater", name: "Cream knit sweater", category: .top, colors: [.cream], fit: .relaxed,
                warmth: .warm, seasons: [.fall, .winter], occasions: [.office, .casual, .brunch],
                photo: .sample("cream-sweater"), wornOn: [day(-200)], addedAt: day(-248)
            ),
            Garment(
                id: "g-brick-top", name: "Brick knit top", category: .top, colors: [.brick], fit: .regular,
                occasions: [.casual, .brunch, .office], photo: .sample("brick-top"), wornOn: [day(-20)],
                addedAt: day(-45)
            ),
            Garment(
                id: "g-black-tee", name: "Black tee", category: .top, colors: [.black], fit: .regular,
                dressiness: .casual, warmth: .light, occasions: [.casual, .concert], photo: .sample("black-tee"),
                laundry: .dirty, addedAt: day(-40)
            ),
            Garment(
                id: "g-wide-jeans", name: "Wide-leg jeans", category: .bottom, colors: [.denim],
                colorNote: "Mid-wash denim", fit: .relaxed, dressiness: .casual,
                occasions: [.casual, .concert, .brunch], notes: "Big patch pocket on the front",
                photo: .sample("wide-jeans"), addedAt: day(-38)
            ),
            Garment(
                id: "g-black-skirt", name: "Black midi skirt", category: .bottom, colors: [.black], fit: .fitted,
                dressiness: .dressy, occasions: [.dateNight, .event, .office], photo: .sample("black-skirt"),
                isArchived: true, wornOn: [day(-70)], addedAt: day(-200)
            ),
            Garment(
                id: "g-blue-dress", name: "Blue floral dress", category: .dress, colors: [.blue, .white],
                colorNote: "Cornflower blue floral", fit: .regular, dressiness: .dressy, warmth: .light,
                seasons: [.spring, .summer], occasions: [.dateNight, .brunch, .event],
                notes: "At the tailor for hemming", photo: .sample("blue-dress"),
                availability: .unavailable(until: day(9)), addedAt: day(-35)
            ),
            Garment(
                id: "g-nude-flats", name: "Nude pointed flats", category: .shoes, colors: [.beige], dressiness: .dressy,
                occasions: [.office, .dateNight, .brunch, .event], photo: .sample("nude-flats"),
                wornOn: [day(-5)], addedAt: day(-110)
            ),
            Garment(
                id: "g-black-heels", name: "Black block heels", category: .shoes, colors: [.black],
                dressiness: .dressy, occasions: [.dateNight, .event, .office], notes: "Low block heel",
                photo: .sample("black-heels"), wornOn: [day(-200), day(-70)], addedAt: day(-250)
            ),
            Garment(
                id: "g-white-sneakers", name: "White sneakers", category: .shoes, colors: [.white],
                dressiness: .casual, occasions: [.casual, .concert, .brunch], photo: .sample("white-sneakers"),
                wornOn: [day(-20)], addedAt: day(-100)
            ),
            Garment(
                id: "g-tan-loafers", name: "Tan loafers", category: .shoes, colors: [.tan],
                occasions: [.office, .casual, .brunch], notes: "Comfortable for long days", photo: .noPhoto,
                addedAt: day(-30)
            ),
            Garment(
                id: "g-burgundy-bag", name: "Burgundy crossbody bag", category: .bag, colors: [.burgundy],
                occasions: [.dateNight, .casual, .brunch, .concert], photo: .sample("burgundy-bag"),
                wornOn: [day(-70)], addedAt: day(-80)
            ),
            Garment(
                id: "g-gray-blazer", name: "Gray blazer", category: .layer, colors: [.gray],
                colorNote: "Heather gray", fit: .regular, dressiness: .dressy, occasions: [.office, .event],
                notes: "Donated, the sleeves were too long", photo: .sample("gray-blazer"),
                ownership: .noLongerOwned, wornOn: [day(-200)], addedAt: day(-300)
            ),
            Garment(
                id: "g-cream-crop", name: "Cream lace crop top", category: .top, colors: [.cream], fit: .fitted,
                warmth: .light, seasons: [.spring, .summer], occasions: [.brunch, .dateNight], brand: "Demo Store",
                sizeLabel: "XS", photo: .noPhoto, ownership: .purchased(.notArrived), addedAt: day(-2)
            ),
            Garment(
                id: "g-camel-trench", name: "Camel trench coat", category: .layer, colors: [.tan], fit: .regular,
                warmth: .warm, seasons: [.spring, .fall], occasions: [.office, .casual],
                photo: .sample("camel-trench"), ownership: .wishlisted, addedAt: day(-12)
            ),
            Garment(
                id: "g-gray-leggings", name: "Old gray leggings", category: .bottom, colors: [.gray],
                colorNote: "Charcoal", fit: .fitted, dressiness: .casual, occasions: [.casual], photo: .noPhoto,
                deletedAt: day(-3), addedAt: day(-400)
            ),
        ]
    }

    static func suitcases(day: (Int) -> Date) -> [Suitcase] {
        [
            Suitcase(
                id: josesHouse, name: "Jose's house", icon: .rolling,
                garmentIDs: ["g-navy-trousers", "g-pink-blouse", "g-navy-cardigan", "g-nude-flats", "g-lace-top"],
                lastUsedAt: day(-1), createdAt: day(-30)
            ),
            Suitcase(
                id: weekend, name: "Weekend", icon: .duffel,
                garmentIDs: [
                    "g-navy-trousers", "g-olive-trousers", "g-wide-jeans", "g-brick-top", "g-cream-sweater",
                    "g-brown-jacket", "g-white-sneakers", "g-black-tee",
                ],
                lastUsedAt: day(-20), createdAt: day(-25)
            ),
            Suitcase(id: springTrip, name: "Spring trip", icon: .weekender, createdAt: day(-5)),
            Suitcase(
                id: gym, name: "Gym", icon: .backpack, garmentIDs: ["g-black-tee", "g-white-sneakers"],
                lastUsedAt: day(-40), createdAt: day(-60)
            ),
            Suitcase(
                id: beach, name: "Beach", icon: .tote, garmentIDs: ["g-blue-dress", "g-white-sneakers"],
                createdAt: day(-90)
            ),
            Suitcase(
                id: oldDorm, name: "Old dorm", icon: .rolling, garmentIDs: ["g-olive-trousers"],
                lastUsedAt: day(-300), isArchived: true, createdAt: day(-400)
            ),
        ]
    }

    static func looks(day: (Int) -> Date) -> [Look] {
        [
            look(
                "o-interview", name: "Interview navy and pink", version: .simple, occasion: .office,
                pieces: ["g-navy-cardigan", "g-pink-blouse", "g-navy-trousers", "g-nude-flats"],
                wornOn: [day(-5)], createdAt: day(-40)
            ),
            look(
                "o-weekend", name: "Weekend olive and brick", version: .simple, occasion: .casual,
                source: .suitcase(weekend),
                pieces: ["g-brown-jacket", "g-brick-top", "g-olive-trousers", "g-white-sneakers"],
                wornOn: [day(-20)], createdAt: day(-25)
            ),
            look(
                "o-lace-date", name: "Lace date night", version: nil, occasion: .dateNight,
                pieces: ["g-lace-top", "g-black-skirt", "g-black-heels", "g-burgundy-bag"],
                wornOn: [day(-70)], createdAt: day(-75)
            ),
            look(
                "o-blazer-office", name: "Gray blazer office", version: .simple, occasion: .office,
                pieces: ["g-gray-blazer", "g-cream-sweater", "g-navy-trousers", "g-black-heels"],
                wornOn: [day(-200)], createdAt: day(-210)
            ),
            look(
                "o-brunch-idea", name: "Brunch with a new layer", version: .somethingNew, occasion: .brunch,
                pieces: ["g-pink-blouse", "g-olive-trousers", "g-tan-loafers"],
                idea: PieceIdea(name: "Cropped cream cardigan", category: .layer, colors: [.cream]),
                createdAt: day(-8)
            ),
            look(
                "o-history-casual", name: nil, version: .simple, occasion: .casual, isSaved: false,
                pieces: ["g-cream-sweater", "g-wide-jeans", "g-white-sneakers"], createdAt: day(-3)
            ),
        ]
    }

    static func look(
        _ id: Look.ID,
        name: String?,
        version: LookVersion?,
        occasion: Occasion,
        source: WardrobeSource = .mainCloset,
        isSaved: Bool = true,
        pieces garmentIDs: [Garment.ID],
        idea: PieceIdea? = nil,
        wornOn: [Date] = [],
        createdAt: Date
    ) -> Look {
        var pieces = garmentIDs.map { garmentID in
            LookPiece(
                id: LookPiece.ID("\(id)-\(garmentID)"),
                content: .garment(garmentID),
                isSameAsSimple: version != nil
            )
        }
        if let idea {
            pieces.append(LookPiece(id: LookPiece.ID("\(id)-idea"), content: .idea(idea)))
        }
        return Look(
            id: id,
            resultID: version == nil ? nil : StyleResult.ID("r-\(id)"),
            version: version,
            pieces: pieces,
            name: name,
            occasion: occasion,
            source: source,
            isSaved: isSaved,
            savedAt: isSaved ? createdAt : nil,
            wornOn: wornOn,
            createdAt: createdAt
        )
    }
}
