import Foundation
import Models
import NookTestSupport
import Testing

/// Phase 30a: the access rules the app applies to what StoreKit reports. Every date is fixed, so
/// "now" moves only when a test moves it.
struct SubscriptionStatusTests {
    let now = TestTime.now
    let id = SubscriptionProducts.monthly

    private func status(
        _ state: SubscriptionState, ends: Int? = 10, grace: Int? = nil, renews: Bool = true
    ) -> SubscriptionStatus {
        SubscriptionStatus(
            state: state, productID: id, expiresAt: ends.map(TestTime.day),
            gracePeriodEndsAt: grace.map(TestTime.day), willAutoRenew: renews, checkedAt: now)
    }

    @Test func trialAndPaidMonthsGiveAccessUntilTheirEnd() {
        for state in [SubscriptionState.trial, .active] {
            let current = status(state, ends: 10)
            #expect(current.hasStylingAccess(at: now))
            #expect(current.hasStylingAccess(at: TestTime.day(9)))
            #expect(!current.hasStylingAccess(at: TestTime.day(10)))
            #expect(!current.hasStylingAccess(at: TestTime.day(11)))
        }
    }

    /// A cached status read long ago never grants past the dates Apple gave.
    @Test func staleCacheNeverGrantsPastItsDates() {
        let cached = status(.trial, ends: 3)
        #expect(cached.effectiveState(at: TestTime.day(2)) == .trial)
        #expect(cached.effectiveState(at: TestTime.day(4)) == .expired)
        #expect(cached.hint(at: TestTime.day(4)) == .expired)
        #expect(!cached.hasStylingAccess(at: TestTime.day(4)))
    }

    @Test func gracePeriodLastsUntilAppleSaysItEnds() {
        let grace = status(.gracePeriod, ends: -1, grace: 5)
        #expect(grace.hasStylingAccess(at: now))
        #expect(!grace.hasStylingAccess(at: TestTime.day(6)))
        #expect(grace.hint(at: now) == .grace)
    }

    @Test func noAccessWithoutAPaidOrFreePeriod() {
        for state in [SubscriptionState.none, .billingRetry, .expired, .revoked] {
            #expect(!status(state, ends: 30).hasStylingAccess(at: now))
        }
        // No end date at all is no access.
        #expect(!status(.active, ends: nil).hasStylingAccess(at: now))
    }

    @Test func mayRenewIsWhatDeleteMyAccountWarnsAbout() {
        #expect(status(.trial).mayRenew)
        #expect(status(.active).mayRenew)
        #expect(status(.gracePeriod).mayRenew)
        #expect(status(.billingRetry).mayRenew)
        #expect(!status(.none).mayRenew)
        #expect(!status(.expired).mayRenew)
        #expect(!status(.revoked).mayRenew)
    }

    @Test func hintsNameEveryState() {
        #expect(EntitlementHint(.billingRetry).rawValue == "billing-retry")
        // 30b: every state, plus the complimentary unlock.
        #expect(
            Set(SubscriptionState.allCases.map(EntitlementHint.init)).union([.complimentary])
                == Set(EntitlementHint.allCases))
    }

    // MARK: 30b: the complimentary unlock

    @Test func theComplimentaryUnlockGivesAccessWithNoEnd() throws {
        var unlocked = SubscriptionStatus.none(at: TestTime.now)
        unlocked.complimentarySince = TestTime.day(-400)
        #expect(unlocked.isComplimentary)
        #expect(unlocked.hasStylingAccess(at: TestTime.day(1_000)))
        #expect(!unlocked.mayRenew)
        #expect(unlocked.hint(at: TestTime.now) == .complimentary)
        // Beside an ended subscription it still counts; the subscription's own state is kept.
        var both = status(.expired, ends: -3)
        both.complimentarySince = TestTime.day(-1)
        #expect(both.hasStylingAccess(at: TestTime.now))
        #expect(both.effectiveState(at: TestTime.now) == .expired)
        // It survives the cache, and a status cached before 30b (no such field) still decodes.
        let data = try JSONEncoder().encode(unlocked)
        #expect(try JSONDecoder().decode(SubscriptionStatus.self, from: data) == unlocked)
        let old = try JSONEncoder().encode(status(.trial, ends: 3))
        var object = try #require(try JSONSerialization.jsonObject(with: old) as? [String: Any])
        object["complimentarySince"] = nil
        let decoded = try JSONDecoder().decode(
            SubscriptionStatus.self, from: try JSONSerialization.data(withJSONObject: object))
        #expect(!decoded.isComplimentary)
    }

    @Test func picturesSpendTheMonthFirstThenCredits() {
        #expect(TryOnFunding.next(hasAccess: true, allowanceLeft: 4, credits: 10) == .allowance)
        #expect(TryOnFunding.next(hasAccess: true, allowanceLeft: nil, credits: nil) == .allowance)
        #expect(TryOnFunding.next(hasAccess: true, allowanceLeft: 0, credits: 10) == .credit)
        #expect(TryOnFunding.next(hasAccess: true, allowanceLeft: 0, credits: 0) == .nothing)
        #expect(TryOnFunding.next(hasAccess: false, allowanceLeft: 4, credits: 2) == .credit)
        #expect(TryOnFunding.next(hasAccess: false, allowanceLeft: 4, credits: nil) == .nothing)
    }

    @Test func statusSurvivesTheCache() throws {
        let original = status(.gracePeriod, ends: -1, grace: 5)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(SubscriptionStatus.self, from: data) == original)
        let cache = InMemorySubscriptionStatusCache()
        #expect(cache.load() == nil)
        cache.save(original)
        #expect(cache.load() == original)
    }

    // MARK: Periods and the offer

    @Test func aMonthIsACalendarMonth() {
        let calendar = TestTime.calendar
        let januaryEnd = calendar.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 12)) ?? now
        let end = SubscriptionPeriod(1, .month).end(from: januaryEnd, calendar: calendar)
        #expect(calendar.dateComponents([.month, .day], from: end) == DateComponents(month: 2, day: 28))
        #expect(SubscriptionPeriod(2, .week).end(from: now, calendar: calendar) == TestTime.day(14))
    }

    @Test func firstChargeIsAfterTheFreeMonthOrToday() {
        let calendar = TestTime.calendar
        var offer = SubscriptionOffer(
            productID: id, displayName: "Styling", displayPrice: "$9.99", period: SubscriptionPeriod(1, .month),
            freeTrial: SubscriptionPeriod(1, .month))
        let month = calendar.date(byAdding: .month, value: 1, to: now)
        #expect(offer.firstCharge(startingAt: now, calendar: calendar) == month)
        offer.freeTrial = nil
        #expect(offer.firstCharge(startingAt: now, calendar: calendar) == now)
    }

    // MARK: Try-on allowance

    @Test func simulatedPicturesAreFreeWhateverTheSubscription() {
        for state in SubscriptionState.allCases {
            #expect(
                TryOnAllowance.current(status: status(state), picturesAreSimulated: true, at: now) == .freeSimulated)
        }
    }

    @Test func realPicturesNeedStylingAccess() {
        let allowances = StylingAllowances(styleMePerDay: 1, swapsAndQuestionsPerDay: 2, tryOnPerMonth: 7)
        #expect(
            TryOnAllowance.current(
                status: status(.trial), picturesAreSimulated: false, at: now, allowances: allowances)
                == .included(perMonth: 7))
        #expect(
            TryOnAllowance.current(status: status(.expired), picturesAreSimulated: false, at: now)
                == .needsStylingAccess)
        // The free month has ended since the status was read.
        #expect(
            TryOnAllowance.current(status: status(.trial, ends: 1), picturesAreSimulated: false, at: TestTime.day(2))
                == .needsStylingAccess)
    }
}
