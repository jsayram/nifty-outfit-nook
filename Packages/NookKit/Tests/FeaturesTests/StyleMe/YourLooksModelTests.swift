import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// A stylist that answers from a script and counts every call, so tests can prove exactly how
/// many requests were sent (LR-05a.4, LR-06.1). Once the script runs out it styles normally.
actor ScriptedStylist: Stylist {
    enum Reply: Sendable {
        /// Style with the mock stylist in this mode.
        case style(MockStylist.Mode)
        case fail(StylistError)
        /// Never answer until cancelled.
        case wait
        /// Answer with this outcome as it is, without checking it.
        case outcome(StyleOutcome)
    }

    private var replies: [Reply]
    private(set) var calls = 0
    private(set) var contexts: [StylingContext] = []

    init(_ replies: [Reply] = []) {
        self.replies = replies
    }

    func style(_ context: StylingContext) async throws(StylistError) -> StyleOutcome {
        calls += 1
        contexts.append(context)
        let reply = replies.isEmpty ? .style(.normal) : replies.removeFirst()
        switch reply {
        case .style(let mode):
            return try await MockStylist(mode: mode).style(context)
        case .fail(let error):
            throw error
        case .wait:
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                throw .cancelled
            }
            throw .cancelled
        case .outcome(let outcome):
            return outcome
        }
    }
}

/// Fixture services with a scripted stylist, on the fixed test clock.
@MainActor
func yourLooksServices(
    _ set: FixtureSet = .demo, behavior: FixtureBehavior = .normal, stylist: ScriptedStylist? = nil
) -> NookServices {
    var services = FixtureServices.make(
        set: set, behavior: behavior, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
    if let stylist { services.stylist = stylist }
    return services
}

/// A request as Style Me builds it from the defaults: Office, Main closet, 58° and rain, Mine +
/// one idea.
func lookRequest(
    _ id: StyleRequest.ID = "req-1",
    source: WardrobeSource = .mainCloset,
    occasion: Occasion = .office,
    weatherChoice: WeatherChoice = .useToday,
    pieceMode: PieceMode = .mineAndOneIdea
) -> StyleRequest {
    StyleRequest(
        id: id, source: source, occasion: occasion, weatherChoice: weatherChoice,
        weather: WeatherSnapshot(condition: .rain, temperatureCelsius: 14.5, observedAt: ClosetTestTime.now),
        preferences: Preferences(pieceMode: pieceMode), createdAt: ClosetTestTime.now)
}

/// A Your looks model with numbered request IDs (req-2, req-3, …) for Try a different outfit.
@MainActor
func yourLooksModel(_ request: StyleRequest = lookRequest()) -> YourLooksModel {
    var next = 1
    return YourLooksModel(
        request: request, now: { ClosetTestTime.now }, calendar: ClosetTestTime.calendar,
        makeID: {
            next += 1
            return StyleRequest.ID("req-\(next)")
        })
}

/// A model that has styled once and settled.
@MainActor
func styledLooks(
    _ request: StyleRequest = lookRequest(), services: NookServices = yourLooksServices()
) async -> YourLooksModel {
    let model = yourLooksModel(request)
    model.start(with: services)
    await model.settle()
    return model
}

@MainActor
struct YourLooksModelTests {
    private let us = ClosetTestTime.locale

    // MARK: Complete

    /// LR-05a.1: one request gives one outfit in three versions that share pieces with Simple.
    @Test func startSendsOneRequestAndShowsThreeVersions() async throws {
        let stylist = ScriptedStylist()
        let model = await styledLooks(services: yourLooksServices(stylist: stylist))
        #expect(model.status == .showing)
        #expect(await stylist.calls == 1)
        #expect(model.requestsSent == 1)
        #expect(model.versions == [.simple, .dressedUp, .somethingNew])
        #expect(model.missing.isEmpty)
        #expect(model.problem == nil)
        let result = try #require(model.result)
        let simple = Set(try #require(result.simple).garmentIDs)
        for look in result.versions.dropFirst() {
            #expect(!simple.isDisjoint(with: look.garmentIDs))
        }
        #expect(model.usablePieces > 0)
    }

    /// The screen calls `start` every time it appears; only the first one sends.
    @Test func startingAgainSendsNothing() async {
        let stylist = ScriptedStylist()
        let services = yourLooksServices(stylist: stylist)
        let model = await styledLooks(services: services)
        model.start(with: services)
        await model.settle()
        #expect(await stylist.calls == 1)
    }

    /// LR-05a.2: switching versions sends nothing and changes the look on screen.
    @Test func switchingVersionsSendsNothing() async throws {
        let stylist = ScriptedStylist()
        let model = await styledLooks(services: yourLooksServices(stylist: stylist))
        #expect(model.currentLook?.version == .simple)
        model.version = .dressedUp
        #expect(model.currentLook?.version == .dressedUp)
        model.version = .somethingNew
        #expect(model.currentLook?.version == .somethingNew)
        #expect(await stylist.calls == 1)
    }

    /// LR-05b.1 and LR-05b.2: one idea with Mine + one idea, none with Only mine.
    @Test func somethingNewFollowsPreferences() async throws {
        let withIdea = await styledLooks()
        let ideas = try #require(withIdea.result?.look(for: .somethingNew)).ideas
        #expect(ideas.count == 1)
        #expect(withIdea.result?.versions.filter { !$0.ideas.isEmpty }.count == 1)

        let onlyMine = await styledLooks(lookRequest(pieceMode: .onlyMine))
        #expect(onlyMine.result?.versions.allSatisfy { $0.ideas.isEmpty } == true)
    }

    /// LR-05b.2: a suitcase stays owned-only and says why, on Something new.
    @Test func aSuitcaseHasNoIdeaAndSaysWhy() async throws {
        let model = await styledLooks(lookRequest(source: .suitcase("s-weekend")))
        #expect(model.status == .showing)
        #expect(model.result?.versions.allSatisfy { $0.ideas.isEmpty } == true)
        #expect(model.result?.notes.contains(.noNewPieceInSuitcase) == true)
        #expect(model.suitcaseName == "Weekend")
        let text = YourLooksText(request: model.request, suitcaseName: model.suitcaseName, locale: us)
        #expect(
            text.line(for: .noNewPieceInSuitcase, now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
                == "Looks from Weekend use only what’s packed, so Something new is made from your own pieces.")
    }

    /// LR-06: every version goes into the look store as unsaved background history.
    @Test func resultsAreKeptAsUnsavedHistory() async throws {
        let services = yourLooksServices()
        let model = await styledLooks(services: services)
        let stored = try await services.looks.looks()
        for look in try #require(model.result).versions {
            let kept = try #require(stored.first { $0.id == look.id })
            #expect(!kept.isSaved)
            #expect(kept.name == nil)
        }
        #expect(model.savedLooks.allSatisfy { $0.isSaved })
    }

    /// RD-09.2: styling from a suitcase makes it a favourite.
    @Test func aSuitcaseIsMarkedAsUsed() async throws {
        let services = yourLooksServices()
        _ = await styledLooks(lookRequest(source: .suitcase("s-weekend")), services: services)
        #expect(try await services.suitcases.suitcase("s-weekend").lastUsedAt == ClosetTestTime.now)
    }

    // MARK: Partial and insufficient

    @Test func aPartialResultSaysWhatIsMissing() async throws {
        let model = await styledLooks(services: yourLooksServices(behavior: .stylistPartial))
        #expect(model.status == .showing)
        #expect(model.versions == [.simple, .dressedUp])
        #expect(model.missing == [MissingVersion(version: .somethingNew, reason: .noOtherOwnedPiece)])
        model.version = .somethingNew
        #expect(model.shownVersion == .simple)
        let text = YourLooksText(request: model.request, suitcaseName: nil, locale: us)
        #expect(
            text.partialLine(missing: model.missing)
                == "No Something new this time. Main closet has no other piece to make another version.")
    }

    /// Jose's house has five pieces and only one pair of shoes, so only some versions fit.
    @Test func aSmallSuitcaseGivesFewerVersions() async throws {
        let model = await styledLooks(lookRequest(source: .suitcase("s-jose")))
        #expect(model.status == .showing)
        #expect(!model.missing.isEmpty)
        #expect(model.versions.count + model.missing.count == 3)
    }

    @Test func theGymSuitcaseIsInsufficient() async throws {
        let model = await styledLooks(lookRequest(source: .suitcase("s-gym")))
        #expect(model.status == .insufficient(InsufficientWardrobe(source: .suitcase("s-gym"), missing: [.bottom])))
        #expect(model.result == nil)
        #expect(model.usablePieces == 2)
    }

    @Test func theForcedInsufficientMode() async throws {
        let model = await styledLooks(services: yourLooksServices(behavior: .stylistInsufficient))
        guard case .insufficient(let wardrobe) = model.status else {
            Issue.record("Expected insufficient, got \(model.status)")
            return
        }
        #expect(wardrobe.missing == [.bottom, .shoes])
    }

    // MARK: Failures

    /// A model failure never claims the closet is too small (LR-05a), and Try again sends once.
    @Test func aFailureCanBeRetried() async throws {
        let stylist = ScriptedStylist([.fail(.notCompleted)])
        let model = await styledLooks(services: yourLooksServices(stylist: stylist))
        #expect(model.status == .failed(.notCompleted))
        #expect(model.result == nil)
        model.retry()
        await model.settle()
        #expect(model.status == .showing)
        #expect(await stylist.calls == 2)
        let contexts = await stylist.contexts
        #expect(contexts.map(\.request.id) == ["req-1", "req-1"])
    }

    @Test func theFailingFixtureFails() async {
        let model = await styledLooks(services: yourLooksServices(behavior: .stylistFails))
        #expect(model.status == .failed(.notCompleted))
    }

    /// Offline: the request is kept, the Saved tab still works, and Retry works once the
    /// connection is back (`offline-once`).
    @Test func offlineThenBackOnline() async throws {
        let offline = await styledLooks(services: yourLooksServices(behavior: .offline))
        #expect(offline.status == .failed(.offline))
        #expect(!offline.savedLooks.isEmpty)

        let once = await styledLooks(services: yourLooksServices(behavior: .offlineOnce))
        #expect(once.status == .failed(.offline))
        once.retry()
        await once.settle()
        #expect(once.status == .showing)
        #expect(once.requestsSent == 2)
    }

    /// The app checks every result before showing it (PRD §8): an idea in Simple fails.
    @Test func aResultThatFailsTheCheckIsNotShown() async throws {
        let request = lookRequest()
        let bad = StyleResult(
            id: "r-bad", requestID: request.id,
            versions: [
                Look(
                    id: "bad-simple", resultID: "r-bad", version: .simple,
                    pieces: [
                        LookPiece(id: "p1", content: .garment("g-navy-trousers"), isSameAsSimple: true),
                        LookPiece(id: "p2", content: .idea(PieceIdea(name: "Blazer", category: .layer))),
                    ],
                    createdAt: ClosetTestTime.now)
            ],
            createdAt: ClosetTestTime.now)
        let services = yourLooksServices(stylist: ScriptedStylist([.outcome(.complete(bad))]))
        let model = await styledLooks(request, services: services)
        #expect(model.status == .failed(.notCompleted))
        #expect(try await services.looks.looks().contains { $0.id == "bad-simple" } == false)
    }

    @Test func aMissingSuitcaseSaysTheRequestChanged() async {
        let model = await styledLooks(lookRequest(source: .suitcase("s-gone")))
        #expect(model.status == .failed(.requestChanged))
    }

    @Test func storesThatFailSendNothing() async {
        let stylist = ScriptedStylist()
        var services = yourLooksServices(behavior: .storesFail)
        services.stylist = stylist
        let model = await styledLooks(services: services)
        #expect(model.status == .failed(.closetUnavailable))
        #expect(await stylist.calls == 0)
    }

    // MARK: Styling and cancelling

    @Test func stylingShowsItsStepsThenCancels() async throws {
        let stylist = ScriptedStylist([.wait])
        let model = yourLooksModel()
        model.start(with: yourLooksServices(stylist: stylist))
        #expect(model.isStyling)
        try await waitUntil { model.status == .styling(.choosing) }
        #expect(model.usablePieces > 0)
        model.cancel()
        #expect(model.status == .failed(.stopped))
        await model.settle()
        #expect(model.status == .failed(.stopped))
        #expect(model.result == nil)
    }

    /// The fixture flag `stylist-waits` keeps it styling until it's cancelled.
    @Test func theWaitingFixtureStaysOnStyling() async throws {
        let model = yourLooksModel()
        model.start(with: yourLooksServices(behavior: .stylistWaits))
        try await waitUntil { model.status == .styling(.choosing) }
        model.cancel()
        #expect(model.status == .failed(.stopped))
    }

    /// An answer that arrives after cancelling is never shown.
    @Test func aLateAnswerIsDropped() async throws {
        let stylist = ScriptedStylist([.wait])
        let services = yourLooksServices(stylist: stylist)
        let model = yourLooksModel()
        model.start(with: services)
        try await waitUntil { model.status == .styling(.choosing) }
        model.cancel()
        await model.settle()
        // Style again works, and only its answer shows.
        model.retry()
        await model.settle()
        #expect(model.status == .showing)
        #expect(await stylist.calls == 2)
    }

    // MARK: Try a different outfit

    /// LR-05a.4: exactly one more request, a new base, all three versions replaced, and the
    /// earlier result kept in background history but not on the Saved tab (LR-06.4).
    @Test func tryADifferentOutfit() async throws {
        let stylist = ScriptedStylist()
        let services = yourLooksServices(stylist: stylist)
        let model = await styledLooks(services: services)
        let first = try #require(model.result)
        model.version = .dressedUp
        model.tryDifferentOutfit()
        await model.settle()
        #expect(await stylist.calls == 2)
        #expect(model.request.id == "req-2")
        let second = try #require(model.result)
        #expect(second.id != first.id)
        #expect(Set(second.versions.map(\.id)).isDisjoint(with: first.versions.map(\.id)))
        #expect(second.simple?.garmentIDs != first.simple?.garmentIDs)
        #expect(model.version == .simple)
        let contexts = await stylist.contexts
        #expect(contexts.last?.shownCombinations.isEmpty == false)

        let stored = try await services.looks.looks()
        for look in first.versions {
            #expect(stored.first { $0.id == look.id }?.isSaved == false)
        }
        #expect(!model.savedLooks.contains { look in first.versions.contains { $0.id == look.id } })
    }

    /// Offline on Try a different outfit: the looks stay, a banner says so, Retry works later.
    @Test func tryADifferentOutfitOfflineKeepsTheLooks() async throws {
        let stylist = ScriptedStylist([.style(.normal), .fail(.offline)])
        let model = await styledLooks(services: yourLooksServices(stylist: stylist))
        let first = model.result
        model.tryDifferentOutfit()
        await model.settle()
        #expect(model.status == .showing)
        #expect(model.problem == .offline)
        #expect(model.result == first)
        model.retry()
        await model.settle()
        #expect(model.problem == nil)
        #expect(model.result != first)
        #expect(await stylist.calls == 3)
    }

    /// Cancel while a different outfit is coming: back to the looks already there.
    @Test func cancellingTryADifferentOutfitKeepsTheLooks() async throws {
        let stylist = ScriptedStylist([.style(.normal), .wait])
        let model = await styledLooks(services: yourLooksServices(stylist: stylist))
        let first = model.result
        model.tryDifferentOutfit()
        try await waitUntil { model.status == .styling(.choosing) }
        model.cancel()
        #expect(model.status == .showing)
        #expect(model.problem == nil)
        #expect(model.result == first)
    }

    // MARK: Saved tab

    /// LR-06.1: the Saved tab lists only saved looks for this source and occasion, and opening it
    /// sends nothing.
    @Test func theSavedTabMatchesSourceAndOccasion() async throws {
        let stylist = ScriptedStylist()
        let model = await styledLooks(services: yourLooksServices(stylist: stylist))
        model.tab = .saved
        #expect(model.savedLooks.map(\.id) == ["o-interview", "o-blazer-office"])
        #expect(await stylist.calls == 1)

        let weekend = await styledLooks(lookRequest(source: .suitcase("s-weekend"), occasion: .casual))
        #expect(weekend.savedLooks.map(\.id) == ["o-weekend"])
        let brunch = await styledLooks(lookRequest(occasion: .brunch))
        #expect(brunch.savedLooks.map(\.id) == ["o-brunch-idea"])
        // LR-06.4: the unsaved casual result from history is never listed.
        let casual = await styledLooks(lookRequest(occasion: .casual))
        #expect(!casual.savedLooks.contains { $0.id == "o-history-casual" })
    }

    // MARK: Saving

    /// Save look names the look and puts it on the Saved tab; tapping Saved takes it out; Undo
    /// puts each change back.
    @Test func saveUnsaveAndUndo() async throws {
        let services = yourLooksServices()
        let model = await styledLooks(services: services)
        let look = try #require(model.currentLook)
        #expect(!model.isSaved(look))

        let saved = try await model.toggleSave(look, name: "Pink & navy")
        #expect(saved == .saved(look.id))
        #expect(model.isSaved(look))
        #expect(model.savedLooks.first?.id == look.id)
        let stored = try await services.looks.look(look.id)
        #expect(stored.isSaved)
        #expect(stored.name == "Pink & navy")

        let unsaved = try await model.toggleSave(look, name: "Pink & navy")
        #expect(unsaved == .unsaved(look.id))
        #expect(!model.isSaved(look))
        #expect(!model.savedLooks.contains { $0.id == look.id })
        #expect(try await services.looks.look(look.id).name == nil)

        try await model.undo(unsaved, name: "Pink & navy")
        #expect(model.isSaved(look))
        try await model.undo(.saved(look.id), name: "Pink & navy")
        #expect(!model.isSaved(look))
        #expect(try await services.looks.look(look.id).isSaved == false)
    }

    /// LR-05b.3: saving Something new keeps the idea tagged and makes nothing owned.
    @Test func savingSomethingNewKeepsTheIdea() async throws {
        let services = yourLooksServices()
        let model = await styledLooks(services: services)
        let before = try await services.closet.garments().count
        model.version = .somethingNew
        let look = try #require(model.currentLook)
        _ = try await model.toggleSave(look, name: "Something new")
        let stored = try await services.looks.look(look.id)
        #expect(stored.isSaved)
        #expect(stored.ideas.count == 1)
        #expect(try await services.closet.garments().count == before)
    }

    @Test func aStoreFailureOnSaveThrows() async throws {
        let model = await styledLooks()
        let look = try #require(model.currentLook)
        let broken = yourLooksModel()
        broken.start(with: yourLooksServices(behavior: .storesFail))
        await broken.settle()
        await #expect(throws: StoreError.unavailable) { try await broken.toggleSave(look, name: "Look") }
    }

    // MARK: Words

    @Test func theRequestLine() {
        let text = { (request: StyleRequest, name: String?) in
            YourLooksText(request: request, suitcaseName: name, locale: us).requestLine
        }
        #expect(text(lookRequest(), nil) == "Office · Main closet · 58° and rain")
        #expect(
            text(lookRequest(source: .suitcase("s-jose"), weatherChoice: .indoors), "Jose's house")
                == "Office · Jose's house · Indoors")
        #expect(text(lookRequest(occasion: .brunch, weatherChoice: .ignore), nil) == "Brunch · Main closet")
        var other = lookRequest(occasion: .other)
        other.occasionNote = "Museum visit"
        #expect(text(other, nil).hasPrefix("Other: Museum visit · Main closet"))
    }

    @Test func versionWords() {
        #expect(YourLooksText.title(of: .simple) == "Simple")
        #expect(YourLooksText.title(of: .dressedUp) == "Dressed up")
        #expect(YourLooksText.title(of: .somethingNew) == "Something new")
        #expect(YourLooksText.description(of: .simple, hasIdea: false) == "Easy and safe")
        #expect(YourLooksText.description(of: .dressedUp, hasIdea: false) == "The same outfit, a little classier")
        #expect(
            YourLooksText.description(of: .somethingNew, hasIdea: true)
                == "The same outfit, plus one piece you don’t have")
        #expect(
            YourLooksText.description(of: .somethingNew, hasIdea: false)
                == "The same outfit, another way with your own pieces")
    }

    /// LR-10: the recent-wear note counts calendar days.
    @Test func recentWearNote() {
        let text = YourLooksText(request: lookRequest(), suitcaseName: nil, locale: us)
        let line = { (days: Int) in
            text.line(
                for: .wornRecently(lastWorn: ClosetTestTime.day(-days)), now: ClosetTestTime.now,
                calendar: ClosetTestTime.calendar)
        }
        #expect(line(0) == "You wore this today")
        #expect(line(1) == "You wore this yesterday")
        #expect(line(5) == "You wore this 5 days ago")
        #expect(
            text.line(for: .requiredColorNotMet(.purple), now: ClosetTestTime.now, calendar: ClosetTestTime.calendar)
                == "Nothing in Main closet could bring in purple here, so this look goes without it.")
    }

    /// LR-08: looks are named when saved, from their main colours and version.
    @Test func savedLookNames() async throws {
        let model = await styledLooks()
        let result = try #require(model.result)
        let text = YourLooksText(request: model.request, suitcaseName: nil, locale: us)
        for look in result.versions {
            let name = text.name(for: look, garments: model.garments)
            #expect(!name.isEmpty)
            #expect((try? NameRules.lookName(name)) == name)
        }
        let dress = Look(
            id: "d", version: .simple, pieces: [LookPiece(id: "p", content: .garment("g-blue-dress"))],
            createdAt: ClosetTestTime.now)
        #expect(text.name(for: dress, garments: model.garments) == "Blue dress")
        let pair = Look(
            id: "p", version: .dressedUp,
            pieces: [
                LookPiece(id: "a", content: .garment("g-pink-blouse")),
                LookPiece(id: "b", content: .garment("g-navy-trousers")),
            ], createdAt: ClosetTestTime.now)
        #expect(text.name(for: pair, garments: model.garments) == "Pink & navy, dressed up")
    }

    /// LR-05a.3: pieces that aren't in Simple are marked Swapped or Added, in words.
    @Test func changedPiecesAreMarked() async throws {
        let model = await styledLooks()
        let result = try #require(model.result)
        let dressedUp = try #require(result.look(for: .dressedUp))
        let changes = YourLooksText.changes(in: dressedUp, simple: result.simple, garments: model.garments)
        let changed = dressedUp.pieces.filter { !$0.isSameAsSimple }
        #expect(!changed.isEmpty)
        #expect(changes.count == changed.count)
        #expect(changes.values.allSatisfy { $0 == .swapped || $0 == .added })
        #expect(YourLooksText.changes(in: try #require(result.simple), simple: result.simple, garments: [:]).isEmpty)
    }
}

/// Waits for a condition the model reaches on its own, a few turns on the main actor away.
///
/// The bound is only a guard against a real hang. In Phases 12b and 17 it ran out at 20 and then
/// 60 seconds on CI and was raised to 600. The cause was the main actor's queue: with every
/// snapshot test of the target drawing there at once, each of the model's turns came only as the
/// target drained. Those tests now take turns (`HeavyMainActorWork`), and these waits take about
/// half a second to two seconds locally while the whole target runs, so 30 seconds is plenty on
/// a slow runner and still fails a real hang quickly.
@MainActor
func waitUntil(_ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(30))
    while !condition() {
        // Throwing ends the test here, so it never goes on to wait for something that won't come.
        guard clock.now < deadline else { throw WaitTimedOut() }
        try await Task.sleep(for: .milliseconds(5))
    }
}

struct WaitTimedOut: Error {}
