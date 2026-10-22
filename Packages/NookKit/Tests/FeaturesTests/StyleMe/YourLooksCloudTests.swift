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

    /// Phase 28: without consent nothing is sent, and Quick ideas made on the phone show at once
    /// with Review; Allow then asks the cloud stylist.
    @Test func withoutConsentQuickIdeasShowAndAllowAsksTheStylist() async throws {
        let stylist = ScriptedStylist()
        let quick = ScriptedStylist()
        var services = cloudServices(stylist, consent: nil)
        services.quickIdeas = quick
        let model = await styledLooks(services: services)
        #expect(model.status == .showing)
        #expect(model.result?.madeBy == .rules)
        #expect(model.quickIdeasReason == .needsConsent)
        #expect(!model.nextRequestUsesStyling)
        #expect(await stylist.calls == 0)
        #expect(await quick.calls == 1)
        model.agreeToStylist()
        await model.settle()
        #expect(services.stylistConsent.current()?.version == StylistConsent.currentVersion)
        #expect(model.status == .showing)
        #expect(model.result?.madeBy == nil)
        #expect(model.quickIdeasReason == nil)
        #expect(await stylist.calls == 1)
    }

    /// The Phase 28 checkpoint on the model: consent off and offline, Style Me still gives Quick
    /// ideas, made only of her own pieces, that suit the rainy 14.5° day, and sends nothing.
    @Test func consentOffAndOfflineStillGiveQuickIdeasFromHerPieces() async throws {
        let stylist = ScriptedStylist()
        let services = cloudServices(stylist, consent: nil)
        let model = yourLooksModel()
        model.start(with: services, connection: ConnectionStatus(.offline))
        await model.settle()
        #expect(model.status == .showing)
        let result = try #require(model.result)
        #expect(result.madeBy == .rules)
        #expect(model.quickIdeasReason == .needsConsent)
        let closet = Dictionary(uniqueKeysWithValues: try await services.closet.garments().map { ($0.id, $0) })
        for look in result.versions {
            #expect(look.garmentIDs.allSatisfy { closet[$0] != nil })
            #expect(look.why?.isEmpty == false)
        }
        let simple = try #require(result.simple).garmentIDs.compactMap { closet[$0] }
        // 14.5° is cool: medium or warm pieces, and a layer for the rain when she has one.
        for piece in simple where [.top, .bottom, .dress, .layer].contains(piece.category) {
            #expect(TemperatureBand.cool.suitableWarmth.contains(piece.warmth), "\(piece.name)")
        }
        #expect(simple.contains { $0.category == .layer })
        #expect(await stylist.calls == 0)

        // With her OK but still offline: Quick ideas again, now saying she's offline.
        services.stylistConsent.save(StylistConsent(agreedAt: TestTime.now))
        model.retry()
        await model.settle()
        #expect(model.quickIdeasReason == .offline)
        #expect(await stylist.calls == 0)
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

    /// Phase 28: a limit or a failed cloud request gives way to Quick ideas, with the reason, and
    /// Ask the stylist (retry) goes back to the cloud.
    @Test func limitsAndProviderFailuresGiveWayToQuickIdeas() async throws {
        let limited = await styledLooks(
            services: cloudServices(ScriptedStylist([.fail(.limited(.rateLimited(retryAfterSeconds: 12)))])))
        #expect(limited.status == .showing)
        #expect(limited.result?.madeBy == .rules)
        #expect(limited.quickIdeasReason == .limited(.rateLimited(retryAfterSeconds: 12)))
        let failed = await styledLooks(services: cloudServices(ScriptedStylist([.fail(.notCompleted)])))
        #expect(failed.status == .showing)
        #expect(failed.quickIdeasReason == .cloudDidNotFinish)
        failed.retry()
        await failed.settle()
        #expect(failed.status == .showing)
        #expect(failed.quickIdeasReason == nil)
        #expect(failed.result?.madeBy == nil)
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
        #expect(gated.aiJobs.activeJobs.isEmpty)
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
        #expect(services.aiJobs.activeJobs.isEmpty)
    }

    /// 27c: the banner, a notification or a relaunch opens Your looks for a request whose job
    /// already finished. It shows that job's looks and asks nothing.
    @Test func aScreenOpenedLaterShowsTheFinishedJobWithoutAskingAgain() async throws {
        let stylist = GatedStylist()
        var services = cloudServices(ScriptedStylist())
        services.stylist = stylist
        let request = lookRequest()
        let model = yourLooksModel(request)
        model.start(with: services)
        while await stylist.waiting == 0 { await Task.yield() }
        model.leave()
        await stylist.open()
        await model.settle()
        let jobID = try #require(model.jobID)
        // She was elsewhere: the banner and Home's dot.
        #expect(services.aiJobs.announcement == jobID)
        #expect(services.aiJobs.unseenResults(.styling) == 1)

        let opened = yourLooksModel(request)
        opened.start(with: services)
        await opened.settle()
        #expect(opened.status == .showing)
        #expect(!opened.isFromHistory)
        #expect(opened.result?.simple?.id == model.result?.simple?.id)
        #expect(await stylist.waiting == 1)
        // Seeing it clears the banner and the dot.
        #expect(services.aiJobs.announcement == nil)
        #expect(services.aiJobs.unseenResults(.styling) == 0)
    }

    @Test func noBannerWhileSheWaitsOnTheScreen() async throws {
        let services = cloudServices(ScriptedStylist())
        let model = await styledLooks(services: services)
        #expect(model.status == .showing)
        #expect(services.aiJobs.announcement == nil)
        #expect(services.aiJobs.unseenResults(.styling) == 0)
    }

    @Test func aCloudJobSaysLeavingIsFineAndOffersANoteOnce() async throws {
        let stylist = ScriptedStylist([.wait])
        let services = cloudServices(stylist)
        let notifier = OfferingNotifier()
        services.aiJobs.notifier = notifier
        let model = yourLooksModel()
        model.start(with: services)
        while await stylist.calls == 0 { await Task.yield() }
        while model.notificationOffer != .offer { await Task.yield() }
        #expect(model.isCloud)
        await model.declineNotifications()
        #expect(model.notificationOffer == .off)
        #expect(await notifier.declined)
        model.cancel()
    }

    /// iOS's answer about notifications can stall (the iOS 27.0 simulator under load, October 2026);
    /// her looks must not wait for it.
    @Test func aNotifierThatNeverAnswersDoesNotHoldUpHerLooks() async throws {
        let services = cloudServices(ScriptedStylist())
        services.aiJobs.notifier = SilentNotifier()
        let model = yourLooksModel()
        model.start(with: services)
        await model.settle()
        #expect(model.status == .showing)
        #expect(model.result?.simple != nil)
        #expect(model.notificationOffer == .off)
    }

    @Test func theNotesSayWhereTheLooksCameFrom() {
        let text = YourLooksText(request: lookRequest(), suitcaseName: nil, locale: TestTime.locale)
        #expect(text.line(for: .fromHistory, now: TestTime.now, calendar: TestTime.calendar).contains("history"))
        #expect(
            text.line(for: .answeredAgain, now: TestTime.now, calendar: TestTime.calendar).contains("Nothing was used"))
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

/// Offers a note until she declines.
actor OfferingNotifier: AIJobNotifier {
    private(set) var declined = false
    func offer() async -> AIJobNotificationOffer { declined ? .off : .offer }
    func requestPermission() async -> Bool { true }
    func declineOffer() async { declined = true }
    func notifyDone(_ kind: AIJob.Kind, id: AIJob.ID) async {}
    func withdraw(_ id: AIJob.ID) async {}
}

/// Never answers a question about notifications, like iOS on a stalled simulator.
struct SilentNotifier: AIJobNotifier {
    func offer() async -> AIJobNotificationOffer {
        await withCheckedContinuation { (_: CheckedContinuation<AIJobNotificationOffer, Never>) in }
    }
    func requestPermission() async -> Bool { false }
    func declineOffer() async {}
    func notifyDone(_ kind: AIJob.Kind, id: AIJob.ID) async {}
    func withdraw(_ id: AIJob.ID) async {}
}
