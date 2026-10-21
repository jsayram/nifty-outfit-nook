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

    @Test func theNotesSayWhereTheLooksCameFrom() {
        let text = YourLooksText(request: lookRequest(), suitcaseName: nil, locale: TestTime.locale)
        #expect(text.line(for: .fromHistory, now: TestTime.now, calendar: TestTime.calendar).contains("history"))
        #expect(text.line(for: .answeredAgain, now: TestTime.now, calendar: TestTime.calendar).contains("Nothing was used"))
    }
}
