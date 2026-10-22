import Fixtures
import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// Phase 30a: Styling access's model against a scripted subscription (the StoreKit side is tested
/// in the app's hosted tests), and the places that read the subscription: Profile, Help, try-on
/// and Delete my account.
@MainActor
struct StylingAccessModelTests {
    let id = SubscriptionProducts.monthly

    private func services(_ subscriptions: ScriptedSubscriptionService) -> NookServices {
        var services = FixtureServices.make(set: .demo, now: TestTime.now, calendar: TestTime.calendar)
        services.subscriptions = subscriptions
        return services
    }

    private func notSubscribed(purchase: PurchaseOutcome? = nil) -> ScriptedSubscriptionService {
        ScriptedSubscriptionService(status: .none(at: TestTime.now), purchase: purchase)
    }

    private var trial: SubscriptionStatus {
        SubscriptionStatus(
            state: .trial, productID: id, expiresAt: TestTime.day(30), willAutoRenew: true, checkedAt: TestTime.now)
    }

    // MARK: Styling access

    @Test func loadsTheStatusAndTheOffer() async {
        let model = StylingAccessModel(now: { TestTime.now })
        await model.load(from: services(notSubscribed()))
        #expect(!model.isLoading)
        #expect(model.state == .none)
        #expect(model.offer == .sample)
        #expect(model.showsOffer)
        #expect(!model.showsManage)
        #expect(model.groupID != nil)
    }

    @Test func buyingStartsTheFreeMonthOnce() async {
        let store = notSubscribed()
        let model = StylingAccessModel(now: { TestTime.now })
        let services = services(store)
        await model.load(from: services)
        await model.purchase(in: services)
        #expect(store.purchaseCount == 1)
        #expect(model.message == .started)
        #expect(model.state == .trial)
        #expect(model.hasAccess)
        #expect(!model.showsOffer)
        #expect(model.showsManage)
    }

    @Test func askToBuyWaitsAndCancelSaysNothing() async {
        let pending = StylingAccessModel(now: { TestTime.now })
        await pending.purchase(in: services(notSubscribed(purchase: .pending)))
        #expect(pending.message == .pending)
        #expect(!pending.hasAccess)

        let cancelled = StylingAccessModel(now: { TestTime.now })
        await cancelled.purchase(in: services(notSubscribed(purchase: .cancelled)))
        #expect(cancelled.message == nil)
        #expect(!cancelled.hasAccess)

        let failed = StylingAccessModel(now: { TestTime.now })
        await failed.purchase(in: services(notSubscribed(purchase: .failed(.offline))))
        #expect(failed.message == .problem(.offline))
    }

    @Test func restoreSaysWhatItFound() async {
        let found = StylingAccessModel(now: { TestTime.now })
        let store = ScriptedSubscriptionService(status: .none(at: TestTime.now), restore: .success(trial))
        await found.restore(in: services(store))
        #expect(found.message == .restored)
        #expect(found.hasAccess)
        #expect(store.restoreCount == 1)

        let nothing = StylingAccessModel(now: { TestTime.now })
        await nothing.restore(in: services(notSubscribed()))
        #expect(nothing.message == .nothingToRestore)

        let offline = StylingAccessModel(now: { TestTime.now })
        await offline.restore(
            in: services(ScriptedSubscriptionService(status: .none(at: TestTime.now), restore: .failure(.offline))))
        #expect(offline.message == .problem(.offline))
    }

    /// A refund or an approved Ask to Buy arrives while the screen is open.
    @Test func followsStoreKitChanges() async {
        let store = notSubscribed(purchase: .pending)
        let services = services(store)
        let model = StylingAccessModel(now: { TestTime.now })
        await model.load(from: services)
        await model.purchase(in: services)
        let following = Task { await model.follow(services) }
        // Approved elsewhere: the update arrives and the waiting message turns into "on".
        for _ in 0..<50 where model.message != .started {
            store.update(trial)
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.state == .trial)
        #expect(model.message == .started)
        store.update(
            SubscriptionStatus(state: .revoked, productID: id, expiresAt: TestTime.day(30), checkedAt: TestTime.now))
        for _ in 0..<50 where model.state != .revoked {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.state == .revoked)
        #expect(!model.hasAccess)
        #expect(model.showsOffer)
        following.cancel()
    }

    @Test func billingRetryPointsToManageNotSubscribe() {
        let model = StylingAccessModel(now: { TestTime.now })
        model.show(
            status: SubscriptionStatus(
                state: .billingRetry, productID: id, expiresAt: TestTime.day(-1), willAutoRenew: true,
                checkedAt: TestTime.now),
            offer: .sample)
        #expect(!model.hasAccess)
        #expect(!model.showsOffer)
        #expect(model.showsManage)
    }

    // MARK: The words

    @Test func offerWordsSayThePriceTrialAndRenewal() {
        #expect(StylingAccessText.offerTitle(.sample) == "1 month free, then $9.99 a month.")
        var noTrial = SubscriptionOffer.sample
        noTrial.freeTrial = nil
        #expect(StylingAccessText.offerTitle(noTrial) == "$9.99 a month.")
        #expect(StylingAccessText.subscribeButton(noTrial) == "Subscribe for $9.99 a month")
        #expect(StylingAccessText.length(SubscriptionPeriod(2, .week)) == "2 weeks")
        #expect(StylingAccessText.length(SubscriptionPeriod(1, .year)) == "1 year")
    }

    // MARK: Elsewhere

    @Test func profileShowsTheSubscription() async {
        let model = ProfileModel()
        model.now = { TestTime.now }
        await model.load(from: services(ScriptedSubscriptionService(status: trial)), locale: TestTime.locale)
        #expect(model.subscription == .trial)
        #expect(StylingAccessText.rowValue(model.subscription) == "Free month")
    }

    @Test func helpSaysWhatIsFreeAndWhatIsPaid() throws {
        let without = try #require(HelpContent.topics(keepsChanges: true).first { $0.id == "freeAndPaid" })
        #expect(without.section == .goodToKnow)
        #expect(without.note?.contains("first month free") == true)
        let with = try #require(
            HelpContent.topics(keepsChanges: true, hasStylingAccess: true).first { $0.id == "freeAndPaid" })
        #expect(with.note?.contains("You have styling access") == true)
    }

    @Test func deleteMyAccountWarnsOnlyWhileASubscriptionMayRenew() async {
        let active = DeleteDataModel(scope: .account)
        await active.load(from: services(ScriptedSubscriptionService(status: trial)))
        #expect(active.subscriptionMayRenew)
        #expect(active.subscriptionGroupID != nil)

        let none = DeleteDataModel(scope: .account)
        await none.load(from: services(notSubscribed()))
        #expect(!none.subscriptionMayRenew)

        let ended = DeleteDataModel(scope: .account)
        await ended.load(
            from: services(
                ScriptedSubscriptionService(
                    status: SubscriptionStatus(
                        state: .expired, productID: id, expiresAt: TestTime.day(-3), checkedAt: TestTime.now))))
        #expect(!ended.subscriptionMayRenew)

        // Delete my data (this iPhone only) never asks StoreKit.
        let device = DeleteDataModel(scope: .thisDevice)
        await device.load(from: services(ScriptedSubscriptionService(status: trial)))
        #expect(!device.subscriptionMayRenew)
    }

    // MARK: 30b: the complimentary unlock and picture credits

    @Test func redeemingACodeTurnsOnComplimentaryAccess() async {
        let subscriptions = notSubscribed()
        var unlocked = SubscriptionStatus.none(at: TestTime.now)
        unlocked.complimentarySince = TestTime.now
        subscriptions.scriptRedemption(unlocked)
        let model = StylingAccessModel(now: { TestTime.now })
        await model.load(from: services(subscriptions))
        #expect(model.showsRedeem)
        await model.redeemed(in: services(subscriptions))
        #expect(model.message == .redeemed)
        #expect(model.isComplimentary)
        #expect(model.hasAccess)
        // No offer, no Manage subscription (nothing bills her), no second Redeem.
        #expect(!model.showsOffer)
        #expect(!model.showsManage)
        #expect(!model.showsRedeem)
        #expect(!model.subscriptionStillBills)
        #expect(StylingAccessText.message(.redeemed) == "Your code is redeemed. Styling access is on.")
    }

    @Test func aRedemptionThatArrivesLaterIsAnnouncedWhenItComes() async {
        // Before iOS 27 the sheet says nothing; the unlock comes through the updates listener.
        let subscriptions = notSubscribed()
        let model = StylingAccessModel(now: { TestTime.now })
        let services = services(subscriptions)
        await model.load(from: services)
        let following = Task { await model.follow(services) }
        await model.redeemed(in: services)
        #expect(model.message == nil)
        var unlocked = SubscriptionStatus.none(at: TestTime.now)
        unlocked.complimentarySince = TestTime.now
        for _ in 0..<50 where model.message == nil {
            subscriptions.update(unlocked)
            await Task.yield()
        }
        following.cancel()
        #expect(model.message == .redeemed)
    }

    @Test func theUnlockSaysASubscriptionStillBills() {
        let model = StylingAccessModel(now: { TestTime.now })
        var both = trial
        both.complimentarySince = TestTime.now
        model.show(status: both, offer: .sample)
        #expect(model.subscriptionStillBills)
        #expect(model.showsManage)
        #expect(StylingAccessText.complimentaryAndSubscription.contains("didn’t cancel it"))
    }

    @Test func packsShowOnlyOncePicturesCostSomethingAndTheBalanceIsKnown() async {
        var services = services(notSubscribed())
        services.credits = ScriptedCreditsService(balance: 4)
        let simulated = StylingAccessModel(now: { TestTime.now })
        await simulated.load(from: services)
        #expect(!simulated.showsPacks)

        services.tryOnIsSimulated = false
        let signedOut = StylingAccessModel(now: { TestTime.now })
        await signedOut.load(from: services)
        // The fixture's paid service can't say her balance, so nothing is offered for sale.
        #expect(signedOut.credits == nil)
        #expect(!signedOut.showsPacks)
        #expect(!signedOut.showsCredits)

        let model = StylingAccessModel(now: { TestTime.now })
        model.show(status: .none(at: TestTime.now), offer: .sample, credits: 0, packs: CreditPackOffer.samples)
        #expect(model.showsPacks)
        #expect(model.showsCredits)
        #expect(StylingAccessText.packButton(CreditPackOffer.samples[0]) == "10 pictures, $2.99")
        #expect(StylingAccessText.creditsDetail(12).hasPrefix("12 left."))
    }

    @Test func buyingAPackSaysWhatWasCreditedOrThatItWillBe() async {
        var services = services(notSubscribed())
        let credits = ScriptedCreditsService(balance: 2)
        services.credits = credits
        let model = StylingAccessModel(now: { TestTime.now })
        model.show(status: .none(at: TestTime.now), offer: .sample, credits: 2, packs: CreditPackOffer.samples)
        await model.buyPack(CreditPacks.small, in: services)
        #expect(model.message == .creditsAdded(10))
        #expect(model.credits == 12)
        #expect(credits.purchases == [CreditPacks.small])
        #expect(StylingAccessText.message(.creditsAdded(10)) == "10 picture credits added.")

        services.credits = ScriptedCreditsService(outcome: .awaitingCredit)
        await model.buyPack(CreditPacks.large, in: services)
        #expect(model.message == .creditsAwaiting)
        #expect(StylingAccessText.message(.creditsAwaiting).contains("Nothing more will be charged"))

        services.credits = ScriptedCreditsService(outcome: .pending)
        await model.buyPack(CreditPacks.large, in: services)
        #expect(model.message == .packPending)

        services.credits = ScriptedCreditsService(outcome: .cancelled)
        await model.buyPack(CreditPacks.large, in: services)
        #expect(model.message == nil)
    }

    @Test func profileSaysComplimentary() async {
        var unlocked = SubscriptionStatus.none(at: TestTime.now)
        unlocked.complimentarySince = TestTime.now
        let model = ProfileModel()
        model.now = { TestTime.now }
        await model.load(from: services(ScriptedSubscriptionService(status: unlocked)), locale: TestTime.locale)
        #expect(model.isComplimentary)
        #expect(
            StylingAccessText.rowValue(model.subscription, isComplimentary: model.isComplimentary) == "Complimentary")
    }

    @Test func tryOnUsesTheMonthFirstThenCredits() async throws {
        var services = services(ScriptedSubscriptionService(status: trial))
        services.tryOnIsSimulated = false
        let look = try await services.looks.look("o-blazer-office")
        func allowance(_ usage: CloudUsage?, status: SubscriptionStatus? = nil) -> TryOnAllowance {
            TryOnAllowance.current(
                status: status ?? trial, picturesAreSimulated: false, at: TestTime.now, usage: usage)
        }
        func usage(left: Int, credits: Int) -> CloudUsage {
            CloudUsage(
                allowances: [
                    UsageAllowance(
                        category: .tryOn, usedToday: 0, limitToday: 3, usedThisMonth: 30 - left, limitThisMonth: 30,
                        resetsAt: nil)
                ], paused: [], credits: credits)
        }
        #expect(
            allowance(usage(left: 5, credits: 8)) == .included(perMonth: StylingAllowances.placeholder.tryOnPerMonth))
        #expect(allowance(usage(left: 0, credits: 8)) == .credits(8))
        #expect(allowance(usage(left: 0, credits: 0)) == .allowanceUsed)
        // Credits work without a subscription.
        #expect(allowance(usage(left: 0, credits: 3), status: .none(at: TestTime.now)) == .credits(3))
        #expect(allowance(usage(left: 0, credits: 0), status: .none(at: TestTime.now)) == .needsStylingAccess)
        #expect(!TryOnAllowance.allowanceUsed.canMake)
        #expect(TryOnAllowance.credits(1).canMake)
        // The sheet reads what's left from the server once pictures are real.
        let model = TryOnModel(look: look, lookName: "Look", garments: [:], saveLook: nil, now: { TestTime.now })
        await model.start(with: services)
        #expect(model.allowance == .included(perMonth: StylingAllowances.placeholder.tryOnPerMonth))
    }

    @Test func tryOnStaysFreeWhileSimulatedAndNeedsAccessOnceReal() async throws {
        var services = services(notSubscribed())
        let look = try await services.looks.look("o-blazer-office")
        let simulated = TryOnModel(look: look, lookName: "Look", garments: [:], saveLook: nil, now: { TestTime.now })
        await simulated.start(with: services)
        #expect(simulated.allowance == .freeSimulated)

        services.tryOnIsSimulated = false
        let real = TryOnModel(look: look, lookName: "Look", garments: [:], saveLook: nil, now: { TestTime.now })
        await real.start(with: services)
        #expect(real.allowance == .needsStylingAccess)
        real.make()
        #expect(real.step == .ready)

        services.subscriptions = ScriptedSubscriptionService(status: trial)
        let subscribed = TryOnModel(look: look, lookName: "Look", garments: [:], saveLook: nil, now: { TestTime.now })
        await subscribed.start(with: services)
        #expect(subscribed.allowance == .included(perMonth: StylingAllowances.placeholder.tryOnPerMonth))
    }
}
