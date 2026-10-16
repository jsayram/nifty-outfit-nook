import Foundation
import Models
import NookTestSupport
import Testing

/// A small closet with a piece in every state, and suitcases of every size (RD-02, FR-67,
/// PRD §8.1 and §8.3).
enum BuilderCloset {
    static let garments: [Garment] = {
        var pieces = [
            Make.garment("g-top", .top, colors: [.white]),
            Make.garment("g-top-2", .top, colors: [.pink]),
            Make.garment("g-bottom", .bottom, colors: [.navy]),
            Make.garment("g-bottom-2", .bottom, colors: [.black]),
            Make.garment("g-dress", .dress, colors: [.blue]),
            Make.garment("g-shoes", .shoes, colors: [.navy]),
            Make.garment("g-shoes-2", .shoes, colors: [.tan]),
            Make.garment("g-layer", .layer, colors: [.brown]),
            Make.garment("g-dirty", .top, colors: [.black], laundry: .dirty),
            Make.garment("g-wish", .top, colors: [.red], ownership: .wishlisted),
            Make.garment("g-gone", .bottom, ownership: .noLongerOwned),
            Make.garment("g-ordered", .shoes, ownership: .purchased(.notArrived)),
        ]
        var away = Make.garment("g-away", .layer, colors: [.navy])
        away.availability = .unavailable(until: TestTime.day(3))
        var deleted = Make.garment("g-deleted", .top)
        deleted.deletedAt = TestTime.day(-1)
        pieces += [away, deleted]
        return pieces
    }()

    static let suitcases: [Suitcase] = [
        Suitcase(
            id: "s-big", name: "Weekend",
            garmentIDs: ["g-top", "g-top-2", "g-bottom", "g-bottom-2", "g-shoes", "g-shoes-2", "g-layer"],
            createdAt: TestTime.now),
        Suitcase(id: "s-small", name: "Gym", garmentIDs: ["g-top", "g-shoes", "g-dirty"], createdAt: TestTime.now),
        Suitcase(id: "s-one", name: "Beach", garmentIDs: ["g-dress", "g-away"], createdAt: TestTime.now),
        Suitcase(id: "s-empty", name: "Spring trip", createdAt: TestTime.now),
        Suitcase(id: "s-wished", name: "Wishes", garmentIDs: ["g-wish", "g-gone"], createdAt: TestTime.now),
        Suitcase(
            id: "s-old", name: "Old", garmentIDs: ["g-top", "g-bottom"], isArchived: true, createdAt: TestTime.now),
    ]

    static func builder(tracksLaundry: Bool = false, garments: [Garment] = garments) -> StyleRequestBuilder {
        StyleRequestBuilder(
            garments: garments, suitcases: suitcases, preferences: Preferences(tracksLaundry: tracksLaundry),
            now: TestTime.now)
    }

    static let weather = WeatherSnapshot(condition: .rain, temperatureCelsius: 14.5, observedAt: TestTime.now)
}

struct StyleRequestDraftTests {
    /// RD-02.3: the defaults are ready to style. LR-03.3: Mine + one idea. LR-04.2: today's weather.
    @Test func aFreshDraftStartsOnTheDefaults() {
        let draft = StyleRequestDraft(preferences: Preferences())
        #expect(draft.source == .mainCloset)
        #expect(draft.occasion == .office)
        #expect(draft.weatherChoice == .useToday)
        #expect(draft.comfort == nil)
        #expect(draft.color == nil)
        #expect(draft.startingPieceID == nil)
        #expect(draft.pieceMode == .mineAndOneIdea)
        #expect(BuilderCloset.builder().check(draft).issues.isEmpty)
    }

    @Test func preferencesStartFromHerSavedChoice() {
        #expect(StyleRequestDraft(preferences: Preferences(pieceMode: .onlyMine)).pieceMode == .onlyMine)
    }
}

struct StyleRequestBuilderTests {
    private let builder = BuilderCloset.builder()

    private func draft(
        _ source: WardrobeSource = .mainCloset,
        start: Garment.ID? = nil,
        mode: PieceMode = .mineAndOneIdea
    ) -> StyleRequestDraft {
        var draft = StyleRequestDraft(preferences: Preferences(pieceMode: mode), source: source)
        draft.startingPieceID = start
        return draft
    }

    // MARK: Building

    /// RD-02.3: one tap with every default gives a request.
    @Test func theDefaultsBuildARequest() throws {
        let request = try builder.build(draft(), weather: BuilderCloset.weather, id: "r-1", createdAt: TestTime.now)
        #expect(request.id == "r-1")
        #expect(request.source == .mainCloset)
        #expect(request.occasion == .office)
        #expect(request.occasionNote == nil)
        #expect(request.weatherChoice == .useToday)
        #expect(request.weather == BuilderCloset.weather)
        #expect(request.comfort == nil)
        #expect(request.color == nil)
        #expect(request.startingPieceID == nil)
        #expect(request.preferences == Preferences())
        #expect(request.allowsNewPieceIdea)
        #expect(request.createdAt == TestTime.now)
    }

    /// LR-04.2: each choice is sent. Indoors and Ignore carry no weather at all.
    @Test(arguments: WeatherChoice.allCases)
    func theWeatherChoiceIsSent(_ choice: WeatherChoice) throws {
        var draft = draft()
        draft.weatherChoice = choice
        let request = try builder.build(draft, weather: BuilderCloset.weather, id: "r", createdAt: TestTime.now)
        #expect(request.weatherChoice == choice)
        #expect(request.weather == (choice == .useToday ? BuilderCloset.weather : nil))
    }

    /// LR-04.3: weather that can't be read still styles.
    @Test func unreadableWeatherStillStyles() throws {
        let request = try builder.build(draft(), weather: nil, id: "r", createdAt: TestTime.now)
        #expect(request.weatherChoice == .useToday)
        #expect(request.weather == nil)
        #expect(request.weatherToUse == nil)
    }

    /// Comfort, colour and Preferences go in as chosen; laundry and the repeat window come from
    /// her saved preferences.
    @Test func everyOptionIsCarried() throws {
        let saved = Preferences(pieceMode: .mineAndOneIdea, repeatWindow: .twoWeeks, tracksLaundry: true)
        let builder = StyleRequestBuilder(
            garments: BuilderCloset.garments, suitcases: BuilderCloset.suitcases, preferences: saved,
            now: TestTime.now)
        var draft = StyleRequestDraft(preferences: saved)
        draft.comfort = .relaxed
        draft.color = ColorWish(.navy, strength: .required, scope: .shoes)
        draft.pieceMode = .onlyMine
        draft.occasion = .dateNight
        let request = try builder.build(draft, weather: nil, id: "r", createdAt: TestTime.now)
        #expect(request.comfort == .relaxed)
        #expect(request.color == ColorWish(.navy, strength: .required, scope: .shoes))
        #expect(request.occasion == .dateNight)
        #expect(request.preferences == Preferences(pieceMode: .onlyMine, repeatWindow: .twoWeeks, tracksLaundry: true))
        #expect(!request.allowsNewPieceIdea)
    }

    /// Other carries her trimmed words; any other occasion carries none, even if words were typed.
    @Test func otherCarriesHerWords() throws {
        var draft = draft()
        draft.occasion = .other
        draft.occasionNote = "  Museum visit  "
        #expect(try builder.build(draft, weather: nil, id: "r", createdAt: TestTime.now).occasionNote == "Museum visit")
        draft.occasionNote = "   "
        #expect(try builder.build(draft, weather: nil, id: "r", createdAt: TestTime.now).occasionNote == nil)
        draft.occasionNote = "Museum visit"
        draft.occasion = .brunch
        #expect(try builder.build(draft, weather: nil, id: "r", createdAt: TestTime.now).occasionNote == nil)
    }

    @Test func otherWordsMustBeOneShortLine() {
        var draft = draft()
        draft.occasion = .other
        draft.occasionNote = String(repeating: "a", count: NameRules.occasionNoteMaximum + 1)
        #expect(
            builder.check(draft).issues == [.occasionNoteInvalid(.tooLong(maximum: NameRules.occasionNoteMaximum))])
        draft.occasionNote = "Museum\nvisit"
        #expect(builder.check(draft).issues == [.occasionNoteInvalid(.controlCharacters)])
        #expect(throws: StyleRequestError.cannotStyle([.occasionNoteInvalid(.controlCharacters)])) {
            try builder.build(draft, weather: nil, id: "r", createdAt: TestTime.now)
        }
    }

    /// LR-05b.2: a suitcase never allows an unowned piece, whatever Preferences says.
    @Test(arguments: PieceMode.allCases)
    func aSuitcaseRequestStaysOwnedOnly(_ mode: PieceMode) throws {
        let request = try builder.build(
            draft(.suitcase("s-big"), mode: mode), weather: nil, id: "r", createdAt: TestTime.now)
        #expect(request.source == .suitcase("s-big"))
        #expect(request.preferences.pieceMode == mode)
        #expect(!request.allowsNewPieceIdea)
    }

    // MARK: Sources

    @Test func theMainClosetCountsEveryPieceInIt() {
        let check = builder.check(draft())
        // In her closet: everything but the wishlist, the piece she no longer has and the deleted one.
        #expect(check.piecesInSource == 11)
        // Usable: not the bought piece that hasn't arrived and not the one that's away.
        #expect(check.usablePieces == 9)
    }

    @Test func aBigSuitcaseHasNoIssues() {
        let check = builder.check(draft(.suitcase("s-big")))
        #expect(check.issues.isEmpty)
        #expect(check.piecesInSource == 7)
        #expect(check.usablePieces == 7)
    }

    /// A small suitcase warns early but still styles.
    @Test func aSmallSuitcaseWarnsEarly() throws {
        let check = builder.check(draft(.suitcase("s-small")))
        #expect(check.issues == [.fewPieces(usable: 3)])
        #expect(check.canStyle)
        #expect(check.warnings == [.fewPieces(usable: 3)])
        _ = try builder.build(draft(.suitcase("s-small")), weather: nil, id: "r", createdAt: TestTime.now)
    }

    /// Tracking laundry takes the dirty piece out of the count.
    @Test func trackedLaundryShrinksASuitcase() {
        let check = BuilderCloset.builder(tracksLaundry: true).check(draft(.suitcase("s-small")))
        #expect(check.issues == [.fewPieces(usable: 2)])
        #expect(check.piecesInSource == 3)
    }

    /// One usable piece can't make a look: the dress is in, the layer is away.
    @Test func tooFewToStyle() {
        let check = builder.check(draft(.suitcase("s-one")))
        #expect(check.issues == [.tooFewToStyle(usable: 1, total: 2)])
        #expect(!check.canStyle)
    }

    /// PRD §8.1: nothing invented for an empty suitcase.
    @Test func anEmptySuitcaseStopsStyling() {
        let check = builder.check(draft(.suitcase("s-empty")))
        #expect(check.issues == [.suitcaseEmpty])
        #expect(check.piecesInSource == 0)
        #expect(!check.canStyle)
    }

    /// Pieces she doesn't have don't count as packed.
    @Test func aSuitcaseOfPiecesSheDoesntHaveIsEmpty() {
        #expect(builder.check(draft(.suitcase("s-wished"))).issues == [.suitcaseEmpty])
    }

    /// FR-67: a missing or archived suitcase never quietly becomes the main closet.
    @Test(arguments: ["s-old", "s-nowhere"])
    func aMissingSuitcaseStopsStyling(_ id: String) {
        let check = builder.check(draft(.suitcase(Suitcase.ID(id))))
        #expect(check.issues == [.suitcaseMissing])
        #expect(!check.canStyle)
    }

    @Test func anEmptyClosetStopsStyling() {
        let empty = BuilderCloset.builder(garments: [])
        #expect(empty.check(draft()).issues == [.closetEmpty])
        #expect(empty.check(draft(.suitcase("s-big"))).issues == [.suitcaseEmpty])
        let onlyWishes = BuilderCloset.builder(garments: [Make.garment("g-wish", .top, ownership: .wishlisted)])
        #expect(onlyWishes.check(draft()).issues == [.closetEmpty])
    }

    /// A closet whose only usable pieces are fewer than a look.
    @Test func aClosetOfOnePiece() {
        let one = BuilderCloset.builder(garments: [Make.garment("g-top", .top)])
        #expect(one.check(draft()).issues == [.tooFewToStyle(usable: 1, total: 1)])
    }

    @Test func activeSuitcasesAreByNameWithoutTheArchivedOne() {
        #expect(builder.activeSuitcases.map(\.name) == ["Beach", "Gym", "Spring trip", "Weekend", "Wishes"])
    }

    // MARK: The starting piece

    /// "Style with this" on a usable piece.
    @Test func aUsableStartingPiece() throws {
        #expect(builder.check(draft(start: "g-bottom")).issues.isEmpty)
        let request = try builder.build(draft(start: "g-bottom"), weather: nil, id: "r", createdAt: TestTime.now)
        #expect(request.startingPieceID == "g-bottom")
    }

    @Test(arguments: [
        ("g-wish", IneligibilityReason.notOwned),
        ("g-gone", .noLongerOwned),
        ("g-ordered", .notArrived),
        ("g-deleted", .deleted),
        ("g-away", .unavailable),
    ])
    func anUnusableStartingPieceSaysWhy(id: String, reason: IneligibilityReason) {
        let check = builder.check(draft(start: Garment.ID(id)))
        #expect(check.issues == [.startingPieceUnusable([reason])])
        #expect(!check.canStyle)
    }

    /// RD-11.2: a dirty piece counts while tracking is off, and not while it's on.
    @Test func aDirtyStartingPieceDependsOnTracking() {
        #expect(builder.check(draft(start: "g-dirty")).issues.isEmpty)
        #expect(
            BuilderCloset.builder(tracksLaundry: true).check(draft(start: "g-dirty")).issues == [
                .startingPieceUnusable([.dirty])
            ])
    }

    /// FR-67: a starting piece must be in the source.
    @Test func aStartingPieceOutsideTheSuitcase() {
        #expect(
            builder.check(draft(.suitcase("s-big"), start: "g-dress")).issues == [
                .startingPieceUnusable([.outsideSource])
            ])
    }

    @Test func aStartingPieceThatIsGoneForGood() {
        #expect(builder.check(draft(start: "g-purged")).issues == [.startingPieceMissing])
    }

    /// The picker offers only usable pieces from the source, by name.
    @Test func startingPieceChoicesAreUsablePiecesInTheSource() {
        #expect(
            builder.usablePieces(in: .suitcase("s-small")).map(\.id) == ["g-dirty", "g-shoes", "g-top"])
        #expect(
            BuilderCloset.builder(tracksLaundry: true).usablePieces(in: .suitcase("s-small")).map(\.id) == [
                "g-shoes", "g-top",
            ])
        #expect(builder.usablePieces(in: .suitcase("s-empty")).isEmpty)
        #expect(builder.usablePieces(in: .mainCloset).count == 9)
    }

    // MARK: Colour

    /// PRD §8.3: a required colour that nothing usable has is said early. Preferred never is.
    @Test func aRequiredColourNothingHas() {
        var draft = draft()
        draft.color = ColorWish(.purple, strength: .required)
        #expect(builder.check(draft).issues == [.requiredColorUnavailable(ColorWish(.purple, strength: .required))])
        #expect(builder.check(draft).canStyle)
        draft.color = ColorWish(.purple, strength: .preferred)
        #expect(builder.check(draft).issues.isEmpty)
    }

    /// The place counts: navy shoes exist, a navy top doesn't, and the away navy layer doesn't count.
    @Test(arguments: [
        (ColorScope.shoes, true), (.top, false), (.bottom, true), (.layer, false), (.anyPiece, true),
        (.wholePalette, true), (.dress, false),
    ])
    func aRequiredColourInAPlace(scope: ColorScope, available: Bool) {
        var draft = draft()
        draft.color = ColorWish(.navy, strength: .required, scope: scope)
        #expect(builder.check(draft).issues.isEmpty == available)
    }

    @Test func colourFitsByKindAndColour() {
        let shoes = Make.garment("g", .shoes, colors: [.tan, .navy])
        #expect(ColorWish(.navy, scope: .shoes).fits(shoes))
        #expect(ColorWish(.navy).fits(shoes))
        #expect(!ColorWish(.navy, scope: .top).fits(shoes))
        #expect(!ColorWish(.black).fits(shoes))
    }

    // MARK: Many combinations

    /// Every combination of source, starting piece, Preferences, laundry and colour: Style me is
    /// allowed exactly when `build` makes a request, every request it makes can be styled
    /// (`StylingContext.make` accepts it), and a new-piece idea is only ever allowed from the
    /// main closet with Mine + one idea.
    @Test func everyCombinationIsConsistent() throws {
        let sources: [WardrobeSource] = [
            .mainCloset, .suitcase("s-big"), .suitcase("s-small"), .suitcase("s-one"), .suitcase("s-empty"),
            .suitcase("s-old"), .suitcase("s-nowhere"),
        ]
        let starts: [Garment.ID?] = [nil, "g-top", "g-dress", "g-dirty", "g-wish", "g-deleted", "g-away", "g-purged"]
        let colors: [ColorWish?] = [
            nil, ColorWish(.navy), ColorWish(.navy, strength: .required, scope: .shoes),
            ColorWish(.pink, strength: .required, scope: .shoes),
        ]
        var built = 0
        var stopped = 0
        for tracksLaundry in [false, true] {
            let builder = BuilderCloset.builder(tracksLaundry: tracksLaundry)
            for source in sources {
                for start in starts {
                    for mode in PieceMode.allCases {
                        for color in colors {
                            for choice in WeatherChoice.allCases {
                                var draft = StyleRequestDraft(preferences: Preferences(pieceMode: mode), source: source)
                                draft.startingPieceID = start
                                draft.color = color
                                draft.weatherChoice = choice
                                let check = builder.check(draft)
                                let request = try? builder.build(
                                    draft, weather: BuilderCloset.weather, id: "r", createdAt: TestTime.now)
                                #expect((request != nil) == check.canStyle)
                                guard let request else {
                                    stopped += 1
                                    continue
                                }
                                built += 1
                                #expect(request.allowsNewPieceIdea == (mode == .mineAndOneIdea && !source.isSuitcase))
                                #expect(request.startingPieceID == start)
                                #expect(request.color == color)
                                #expect(request.weatherChoice == choice)
                                #expect(request.preferences.tracksLaundry == tracksLaundry)
                                let context = try StylingContext.make(
                                    request: request, garments: BuilderCloset.garments,
                                    suitcases: BuilderCloset.suitcases, looks: [], usualFit: nil,
                                    now: TestTime.now, calendar: TestTime.calendar)
                                #expect(context.eligibleGarments.count >= StyleRequestBuilder.minimumPieces)
                                #expect(context.eligibleGarments.count == check.usablePieces)
                            }
                        }
                    }
                }
            }
        }
        #expect(built > 0)
        #expect(stopped > 0)
        #expect(built + stopped == 2 * sources.count * starts.count * PieceMode.allCases.count * colors.count * 3)
    }
}
