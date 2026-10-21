import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Your looks with the cloud stylist (Phase 27a): consent first, "From your history" before a
/// paid request (FR-58), New ideas, the why line, and limits and failures said calmly.
@MainActor
struct YourLooksCloudTests {
    /// Fixture services with the cloud stylist's switches on and a scripted stylist behind them.
    func cloudServices(_ stylist: ScriptedStylist, consent: StylistConsent? = StylistConsent(agreedAt: TestTime.now))
        -> NookServices
    {
        var services = yourLooksServices(stylist: stylist)
        services.cloudStyling = true
        services.stylistConsent = InMemoryStylistConsentStore(consent)
        return services
    }

    /// The mock stylist's outcome, as the cloud stylist returns it: with why lines and the intent.
    func cloudOutcome(_ request: StyleRequest, services: NookServices) async throws -> StyleOutcome {
        let context = try StylingContext.make(
            request: request, garments: try await services.closet.garments(),
            suitcases: try await services.suitcases.suitcases(), looks: [], usualFit: nil, now: TestTime.now,
            calendar: TestTime.calendar)
        guard case .complete(var result) = try await MockStylist().style(context) else {
            Issue.record("The demo closet should make three versions")
            return .complete(StyleResult(id: "r-x", requestID: request.id, versions: [], createdAt: TestTime.now))
        }
        result.versions = result.versions.map { look in
            var look = look
            look.why = "Why \(look.version?.rawValue ?? "")"
            look.intent = StyleIntent(request)
            return look
        }
        return .complete(result)
    }

    @Test func withoutConsentNothingIsSentAndAllowStylesRightAway() async throws {
        let stylist = ScriptedStylist([.fail(.needsConsent)])
        let services = cloudServices(stylist, consent: nil)
        let model = await styledLooks(services: services)
        #expect(model.status == .failed(.needsConsent))
        model.agreeToStylist()
        await model.settle()
        #expect(services.stylistConsent.current()?.version == StylistConsent.currentVersion)
        #expect(model.status == .showing)
        #expect(await stylist.calls == 2)
    }

    @Test func anEarlierResultFromHerHistoryIsShownWithoutAskingAgain() async throws {
        var services = cloudServices(ScriptedStylist())
        let request = lookRequest()
        let outcome = try await cloudOutcome(request, services: services)
        services.stylist = ScriptedStylist([.outcome(outcome)])
        // The first request is answered by the stylist and kept as history.
        let model = await styledLooks(request, services: services)
        #expect(model.status == .showing)
        #expect(!model.isFromHistory)
        #expect(model.originalLook?.why == "Why simple")

        // The same request again: from her history, nothing sent.
        let counting = ScriptedStylist()
        var again = services
        again.stylist = counting
        let second = await styledLooks(lookRequest("req-9"), services: again)
        #expect(second.status == .showing)
        #expect(second.isFromHistory)
        #expect(await counting.calls == 0)
        #expect(second.result?.simple?.id == model.result?.simple?.id)

        // New ideas asks the stylist.
        second.tryDifferentOutfit()
        await second.settle()
        #expect(await counting.calls == 1)
        #expect(!second.isFromHistory)
    }

    @Test func historyIsNotUsedWhileStyleMeStylesOnThePhone() async throws {
        let stylist = ScriptedStylist()
        var services = cloudServices(stylist)
        let request = lookRequest()
        services.stylist = ScriptedStylist([.outcome(try await cloudOutcome(request, services: services))])
        _ = await styledLooks(request, services: services)
        services.cloudStyling = false
        services.stylist = stylist
        _ = await styledLooks(lookRequest("req-9"), services: services)
        #expect(await stylist.calls == 1)
    }

    @Test func limitsAndProviderFailuresAreSaidCalmly() async throws {
        let limited = await styledLooks(
            services: cloudServices(ScriptedStylist([.fail(.limited(.rateLimited(retryAfterSeconds: 12)))])))
        #expect(limited.status == .failed(.limited(.rateLimited(retryAfterSeconds: 12))))
        let failed = await styledLooks(services: cloudServices(ScriptedStylist([.fail(.notCompleted)])))
        #expect(failed.status == .failed(.notCompleted))
        failed.retry()
        await failed.settle()
        #expect(failed.status == .showing)
    }

    /// Jose, 21 October 2026: leaving Your looks doesn't stop a cloud request. Its looks land in
    /// her history, the screen shows them if she comes back, and a new Style me finds them.
    @Test func leavingTheScreenDoesNotStopACloudRequestAndItsLooksAreKept() async throws {
        let stylist = GatedStylist()
        let services = cloudServices(ScriptedStylist())
        var gated = services
        gated.stylist = stylist
        let request = lookRequest()
        let model = yourLooksModel(request)
        model.start(with: gated)
        while await stylist.waiting == 0 { await Task.yield() }
        model.leave()
        #expect(model.isStyling)
        let before = try await services.looks.looks().count
        await stylist.open()
        await model.settle()
        #expect(model.status == .showing)
        #expect(try await services.looks.looks().count == before + 3)
        #expect(gated.stylingJobs.runningCount == 0)
    }

    @Test func herCancelStopsACloudRequest() async throws {
        let stylist = ScriptedStylist([.wait])
        let services = cloudServices(stylist)
        let model = yourLooksModel()
        model.start(with: services)
        while await stylist.calls == 0 { await Task.yield() }
        model.cancel()
        #expect(model.status == .failed(.stopped))
        await model.settle()
        #expect(services.stylingJobs.runningCount == 0)
    }

    @Test func theNotesSayWhereTheLooksCameFrom() {
        let text = YourLooksText(request: lookRequest(), suitcaseName: nil, locale: TestTime.locale)
        #expect(text.line(for: .fromHistory, now: TestTime.now, calendar: TestTime.calendar).contains("history"))
        #expect(text.line(for: .answeredAgain, now: TestTime.now, calendar: TestTime.calendar).contains("Nothing was used"))
    }
}

/// A stylist that answers (with the mock stylist) only when the test opens it.
actor GatedStylist: Stylist {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private(set) var waiting = 0

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }

    func style(_ context: StylingContext) async throws(StylistError) -> StyleOutcome {
        waiting += 1
        if !isOpen { await withCheckedContinuation { waiters.append($0) } }
        return try await MockStylist().style(context)
    }
}
