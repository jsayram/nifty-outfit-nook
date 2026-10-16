import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// A stylist that only counts calls, to prove Style Me sends nothing until 10b (RD-02.1).
actor CountingStylist: Stylist {
    private(set) var calls = 0

    func style(_ context: StylingContext) async throws(StylistError) -> StyleOutcome {
        calls += 1
        throw .notCompleted
    }
}

/// Fixture services for Style Me on the fixed test clock.
@MainActor
func styleMeServices(
    _ set: FixtureSet = .demo,
    behavior: FixtureBehavior = .normal,
    weather: FixtureWeatherState? = nil,
    laundry: FixtureLaundryState? = nil
) -> NookServices {
    FixtureServices.make(
        set: set, behavior: behavior, weather: weather, laundry: laundry, now: TestTime.now,
        calendar: TestTime.calendar)
}

/// A Style Me model loaded the way the screen loads it.
@MainActor
func loadedStyleMe(
    _ services: NookServices = styleMeServices(), startingPieceID: Garment.ID? = nil
) async -> StyleMeModel {
    let model = StyleMeModel(startingPieceID: startingPieceID)
    await model.load(from: services, now: TestTime.now)
    return model
}

@MainActor
struct StyleMeModelTests {
    private let us = TestTime.locale

    /// RD-02: the defaults are ready to style, with today's weather (LR-04.1) and Lily's
    /// Preferences default (LR-03.3).
    @Test func theDemoOpensOnTheDefaults() async {
        let model = await loadedStyleMe()
        #expect(model.phase == .loaded)
        #expect(model.check.issues.isEmpty)
        #expect(model.check.piecesInSource == 17)
        #expect(model.canStyle)
        #expect(model.usualFit == .relaxed)
        #expect(model.weather.snapshot?.condition == .rain)
        #expect(model.draft == StyleRequestDraft(preferences: Preferences()))
        let text = model.text(locale: us)
        #expect(text.sourceName == "Main closet")
        #expect(text.sourceDetail == "17 pieces")
        #expect(text.occasionValue == "Office")
        #expect(text.startingPieceValue == "None")
        #expect(text.startingPieceDetail == "Optional · from Main closet")
        #expect(text.comfortValue == "Usual fit")
        #expect(text.comfortLine == "Just for this outfit.")
        #expect(text.colorValue == "Any")
        #expect(text.preferencesValue == "Mine + one idea")
        #expect(text.buttonCaption == "Uses 1 styling request.")
    }

    /// RD-02.1: opening Style Me, changing options and building the request call no stylist.
    @Test func nothingIsSentUntilStyleMe() async throws {
        var services = styleMeServices()
        let stylist = CountingStylist()
        services.stylist = stylist
        let model = await loadedStyleMe(services)
        model.update { $0.comfort = .fitted }
        model.choose(source: .suitcase("s-weekend"))
        let request = try #require(model.makeRequest(id: "r-1", now: TestTime.now))
        #expect(request.source == .suitcase("s-weekend"))
        #expect(await stylist.calls == 0)
    }

    /// RD-02.3 with every choice changed: the request carries exactly what she picked.
    @Test func theRequestCarriesEveryChoice() async throws {
        let model = await loadedStyleMe()
        model.update { draft in
            draft.occasion = .other
            draft.occasionNote = "Museum visit"
            draft.weatherChoice = .indoors
            draft.comfort = .fitted
            draft.color = ColorWish(.navy, strength: .required, scope: .bottom)
            draft.pieceMode = .onlyMine
            draft.startingPieceID = "g-navy-trousers"
        }
        let request = try #require(model.makeRequest(id: "r-1", now: TestTime.now))
        #expect(request.occasion == .other)
        #expect(request.occasionNote == "Museum visit")
        #expect(request.weatherChoice == .indoors)
        #expect(request.weather == nil)
        #expect(request.comfort == .fitted)
        #expect(request.color == ColorWish(.navy, strength: .required, scope: .bottom))
        #expect(request.preferences.pieceMode == .onlyMine)
        #expect(!request.allowsNewPieceIdea)
        #expect(request.startingPieceID == "g-navy-trousers")
        let text = model.text(locale: us)
        #expect(text.comfortLine == "Today: fitted (you usually like relaxed)")
        #expect(text.colorValue == "Navy · bottom · required")
        #expect(text.occasionValue == "Other: Museum visit")
        #expect(text.preferencesValue == "Only mine")
    }

    /// No names go into the request: the suitcase and the piece are IDs only (DATA_MAP.md).
    @Test func theRequestHoldsNoNames() async throws {
        let model = await loadedStyleMe(startingPieceID: "g-navy-trousers")
        model.choose(source: .suitcase("s-jose"))
        let request = try #require(model.makeRequest(id: "r-1", now: TestTime.now))
        let json = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        #expect(json.contains("s-jose"))
        #expect(!json.contains("Jose"))
        #expect(!json.contains("Navy dress pants"))
        #expect(!json.contains("Lily"))
    }

    /// "Style me with it" from garment detail: the piece is the starting piece.
    @Test func styleWithThisSetsTheStartingPiece() async throws {
        let model = await loadedStyleMe(startingPieceID: "g-navy-trousers")
        #expect(model.startingPiece?.name == "Navy dress pants")
        #expect(model.check.issues.isEmpty)
        let text = model.text(locale: us)
        #expect(text.startingPieceValue == "Navy dress pants")
        #expect(text.startingPieceDetail == "Your looks are built around it")
        #expect(model.makeRequest(now: TestTime.now)?.startingPieceID == "g-navy-trousers")
    }

    /// RD-11.2: with tracking on, a piece in the wash can't start a look, and the screen says why.
    @Test func aStartingPieceInTheWash() async {
        let model = await loadedStyleMe(styleMeServices(laundry: .some), startingPieceID: "g-lace-top")
        #expect(model.check.issues == [.startingPieceUnusable([.dirty])])
        #expect(!model.canStyle)
        #expect(model.makeRequest(now: TestTime.now) == nil)
        let text = model.text(locale: us)
        #expect(text.startingPieceProblem == "In the wash")
        let notice = text.notice(for: model.check.issues[0])
        #expect(notice.message == "White lace top can’t be your starting piece. In the wash.")
        #expect(notice.actions == [.chooseStartingPiece, .clearStartingPiece])
        // The picker never offers it.
        #expect(!model.startingPieceChoices.map(\.id).contains("g-lace-top"))
        model.update { $0.startingPieceID = nil }
        #expect(model.canStyle)
    }

    /// FR-67: switching to a suitcase the piece isn't packed in keeps the piece and says so.
    @Test func aStartingPieceOutsideTheNewSource() async {
        let model = await loadedStyleMe(startingPieceID: "g-pink-blouse")
        model.choose(source: .suitcase("s-weekend"))
        #expect(model.check.issues == [.startingPieceUnusable([.outsideSource])])
        #expect(model.text(locale: us).startingPieceProblem == "Not packed in Weekend")
    }

    // MARK: Sources

    @Test func aSuitcaseShowsItsCountAndScope() async {
        let model = await loadedStyleMe()
        model.choose(source: .suitcase("s-weekend"))
        #expect(model.check.issues.isEmpty)
        let text = model.text(locale: us)
        #expect(text.sourceName == "Weekend")
        #expect(text.sourceDetail == "8 pieces · Suitcase only")
        #expect(text.preferencesLine == "From a suitcase, every piece is one you packed.")
        #expect(model.makeRequest(now: TestTime.now)?.allowsNewPieceIdea == false)
    }

    /// A small suitcase warns early and still styles.
    @Test func josesHouseHasFewPieces() async {
        let model = await loadedStyleMe()
        model.choose(source: .suitcase("s-jose"))
        #expect(model.check.issues == [.fewPieces(usable: 5)])
        #expect(model.canStyle)
        let notice = model.text(locale: us).notice(for: .fewPieces(usable: 5))
        #expect(
            notice.message == "Jose's house has 5 pieces you can use today, so you may get fewer than three versions.")
    }

    @Test func anEmptySuitcaseStopsStyleMe() async {
        let model = await loadedStyleMe()
        model.choose(source: .suitcase("s-spring"))
        #expect(model.check.issues == [.suitcaseEmpty])
        #expect(!model.canStyle)
        let text = model.text(locale: us)
        #expect(text.sourceDetail == "Empty · Suitcase only")
        let notice = text.notice(for: .suitcaseEmpty)
        #expect(notice.title == "Spring trip is empty")
        #expect(notice.actions == [.addPieces, .chooseSource])
        #expect(text.buttonCaption == "Style me works once the note above is sorted.")
    }

    /// The beach suitcase: the dress is at the tailor, so only the sneakers are usable.
    @Test func tooFewUsablePieces() async {
        let model = await loadedStyleMe()
        model.choose(source: .suitcase("s-beach"))
        #expect(model.check.issues == [.tooFewToStyle(usable: 1, total: 2)])
        let notice = model.text(locale: us).notice(for: model.check.issues[0])
        #expect(notice.message == "Only 1 of 2 pieces in Beach can be used today. A look needs at least 2.")
    }

    @Test func theSourceSheetListsActiveSuitcasesByName() async {
        let model = await loadedStyleMe()
        #expect(model.activeSuitcases.map(\.name) == ["Beach", "Gym", "Jose's house", "Spring trip", "Weekend"])
        #expect(model.pieceCount(in: .mainCloset) == 17)
        #expect(model.pieceCount(in: .suitcase("s-spring")) == 0)
    }

    // MARK: States

    /// A fresh install: nothing to style, and the way forward is Add a piece.
    @Test func anEmptyCloset() async {
        let model = await loadedStyleMe(styleMeServices(.empty))
        #expect(model.phase == .loaded)
        #expect(model.check.issues == [.closetEmpty])
        #expect(!model.canStyle)
        #expect(model.makeRequest(now: TestTime.now) == nil)
        let notice = model.text(locale: us).notice(for: .closetEmpty)
        #expect(notice.title == "Your closet is empty")
        #expect(notice.actions == [.addPiece])
    }

    /// LR-04.3: weather that can't be read is said honestly and styling still works.
    @Test func weatherUnavailable() async throws {
        let model = await loadedStyleMe(styleMeServices(weather: .unavailable))
        #expect(model.weather == .unavailable)
        #expect(model.canStyle)
        let request = try #require(model.makeRequest(now: TestTime.now))
        #expect(request.weatherChoice == .useToday)
        #expect(request.weather == nil)
    }

    @Test func aStoreFailureShowsTheErrorState() async {
        let model = await loadedStyleMe(styleMeServices(behavior: .storesFail))
        #expect(model.phase == .failed)
        #expect(!model.canStyle)
        #expect(model.makeRequest(now: TestTime.now) == nil)
    }

    @Test func noServicesIsAFailureNotACrash() async {
        let model = StyleMeModel()
        await model.load(from: .unavailable)
        #expect(model.phase == .failed)
        #expect(model.weather == .unavailable)
    }

    // MARK: Request scope

    /// RD-02.4, LR-04.2, LR-18.2: a new Style Me starts on the defaults again.
    @Test func aNewStyleMeStartsFresh() async {
        let services = styleMeServices()
        let first = await loadedStyleMe(services)
        first.update { draft in
            draft.comfort = .fitted
            draft.color = ColorWish(.pink)
            draft.weatherChoice = .ignore
            draft.pieceMode = .onlyMine
        }
        let second = await loadedStyleMe(services)
        #expect(second.draft == StyleRequestDraft(preferences: Preferences()))
        #expect(second.text(locale: us).comfortLine == "Just for this outfit.")
    }

    /// Coming back from Add a piece or the results reloads the closet and keeps her choices.
    @Test func reloadingKeepsHerChoices() async {
        let services = styleMeServices()
        let model = await loadedStyleMe(services)
        model.update { draft in
            draft.comfort = .comfortable
            draft.occasion = .brunch
        }
        let before = model.draft
        await model.load(from: services, now: TestTime.now)
        #expect(model.draft == before)
    }

    /// Preferences start from her saved choice.
    @Test func preferencesStartFromHerProfile() async throws {
        let services = styleMeServices()
        var profile = try await services.profile.profile()
        profile.preferences.pieceMode = .onlyMine
        try await services.profile.save(profile)
        let model = await loadedStyleMe(services)
        #expect(model.draft.pieceMode == .onlyMine)
    }

    /// The large closet: checking a change stays quick with 2,400 pieces.
    @Test(.heavyMainActorWork) func theLargeClosetChecksQuickly() async {
        let model = await loadedStyleMe(styleMeServices(.large))
        #expect(model.phase == .loaded)
        let elapsed = SpeedCheck.fastest {
            for occasion in Occasion.allCases {
                model.update { $0.occasion = occasion }
            }
            _ = model.startingPieceChoices
        }
        #expect(elapsed < SpeedCheck.limit(.milliseconds(500)), "Checking 7 changes took \(elapsed)")
    }
}
