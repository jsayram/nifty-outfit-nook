import Foundation
import Models
import Observation

/// Styling access (Phase 30a, `access.html` and `paywall.html`): her subscription as StoreKit
/// reports it, the offer when she has none, and buying and restoring. The screen shows it; the
/// App Store's own sheet confirms every purchase.
///
/// 30b: the complimentary unlock (redeemed with an App Store offer code in Apple's own sheet), her
/// picture-credit balance from the server, and the picture packs, once try-on pictures cost
/// something.
@Observable
final class StylingAccessModel {
    enum Busy: Equatable {
        case none
        case purchasing
        case restoring
        /// 30b: buying this pack.
        case buyingPack(String)
    }

    /// Something to tell her after a tap.
    enum Message: Equatable {
        /// Ask to Buy, or another approval: it arrives later.
        case pending
        /// Bought: styling access is on.
        case started
        /// Restore found a subscription.
        case restored
        /// Restore found nothing for this Apple Account.
        case nothingToRestore
        /// 30b: a code was redeemed: complimentary styling access is on.
        case redeemed
        /// 30b: a pack was credited: this many pictures.
        case creditsAdded(Int)
        /// 30b: a pack was paid for, but the server hasn't credited it yet. It will be.
        case creditsAwaiting
        /// 30b: a pack waits for approval (Ask to Buy).
        case packPending
        case problem(SubscriptionProblem)
    }

    private(set) var status: SubscriptionStatus
    private(set) var offer: SubscriptionOffer?
    /// Why the offer couldn't be read, if it couldn't.
    private(set) var offerProblem: SubscriptionProblem?
    private(set) var isLoading = true
    private(set) var busy = Busy.none
    var message: Message?
    private(set) var groupID: String?
    /// 30b: her picture credits, from the server. Nil when it couldn't say (signed out, offline).
    private(set) var credits: Int?
    /// 30b: the picture packs, while they're on sale.
    private(set) var packs: [CreditPackOffer] = []
    /// 30b: packs are sold once try-on pictures cost something (Phase 33); until then pictures
    /// are free and simulated.
    private(set) var sellsPacks = false
    /// 32b (L9): a build with no backend settings. Nothing is offered or sold, because a purchase
    /// could never be matched to an account.
    private(set) var cloudUnavailable = false
    /// 30b: Apple's offer code sheet closed and the unlock may still be on its way.
    private var awaitingRedemption = false
    /// The clock. Tests and snapshots fix it.
    @ObservationIgnored let now: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
        status = .none(at: now())
    }

    /// Whether she has styling access now.
    var hasAccess: Bool { status.hasStylingAccess(at: now()) }

    /// The state as she has it now: a cached period that has ended reads as expired.
    var state: SubscriptionState { status.effectiveState(at: now()) }

    /// Whether the offer and the Subscribe button show: whenever she has no access, except while
    /// Apple is still trying a payment (then she fixes the payment in Manage subscription).
    var showsOffer: Bool { !cloudUnavailable && !hasAccess && state != .billingRetry }

    /// Whether there's a subscription for Manage subscription to show.
    var showsManage: Bool { state != .none }

    /// 30b: whether she has the complimentary unlock.
    var isComplimentary: Bool { status.isComplimentary }

    /// 30b: Redeem a code shows until she has the complimentary unlock.
    var showsRedeem: Bool { !isComplimentary }

    /// 30b: the complimentary unlock doesn't cancel a subscription that still renews (PRD 14.2).
    var subscriptionStillBills: Bool { isComplimentary && status.mayRenew }

    /// 30b: whether the credit balance shows: while packs are sold, or whenever she has some.
    var showsCredits: Bool {
        guard let credits else { return false }
        return sellsPacks || credits > 0
    }

    /// 30b: whether the packs show: on sale, and her balance is known (so a claim can reach the
    /// server once she's bought one).
    var showsPacks: Bool { sellsPacks && credits != nil && !packs.isEmpty }

    /// Shows a fixed state, for snapshot tests.
    func show(
        status: SubscriptionStatus, offer: SubscriptionOffer?, offerProblem: SubscriptionProblem? = nil,
        credits: Int? = nil, packs: [CreditPackOffer] = []
    ) {
        self.status = status
        self.offer = offer
        self.offerProblem = offerProblem
        self.credits = credits
        self.packs = packs
        sellsPacks = !packs.isEmpty
        isLoading = false
    }

    /// The cached status at once, then StoreKit's, and the offer.
    func load(from services: NookServices) async {
        if services.cloudUnavailable {
            cloudUnavailable = true
            isLoading = false
            return
        }
        let subscriptions = services.subscriptions
        status = await subscriptions.cachedStatus()
        status = await subscriptions.refresh()
        groupID = await subscriptions.subscriptionGroupID()
        do {
            offer = try await subscriptions.offer()
            offerProblem = nil
        } catch {
            offerProblem = error
        }
        await loadCredits(from: services)
        isLoading = false
    }

    /// 30b: her balance from the server, and the packs while they're sold.
    private func loadCredits(from services: NookServices) async {
        sellsPacks = !services.tryOnIsSimulated
        // A pack paid for earlier but not credited yet (she was signed out, or offline) is
        // claimed now, before the balance is read.
        _ = await services.credits.recoverUnfinished()
        credits = (try? await services.paid.usage())?.credits
        if sellsPacks, packs.isEmpty {
            packs = (try? await services.credits.packs()) ?? []
        }
    }

    /// Follows StoreKit's changes while the screen is open: a renewal, a refund, an approved Ask
    /// to Buy.
    func follow(_ services: NookServices) async {
        for await update in await services.subscriptions.statusUpdates() {
            let hadAccess = hasAccess
            let wasComplimentary = isComplimentary
            status = update
            if awaitingRedemption, !wasComplimentary, isComplimentary {
                awaitingRedemption = false
                message = .redeemed
            } else if !hadAccess, hasAccess, busy == .none, message == .pending {
                message = .started
            }
        }
    }

    /// 30b: follows her balance while the screen is open (a pack credited in the background).
    func followCredits(_ services: NookServices) async {
        for await balance in await services.credits.balanceUpdates() {
            credits = balance
        }
    }

    /// 30b: after Apple's offer code sheet closes. The sheet says nothing about what was redeemed
    /// before iOS 27, so the status is read again; if the unlock is still on its way, `follow`
    /// says so when it arrives. Closing the sheet without a code says nothing.
    func redeemed(in services: NookServices) async {
        let wasComplimentary = isComplimentary
        awaitingRedemption = !wasComplimentary
        status = await services.subscriptions.redeemedOfferCode()
        if !wasComplimentary, isComplimentary {
            awaitingRedemption = false
            message = .redeemed
        }
    }

    /// 30b: buys a picture pack, which the server then credits.
    func buyPack(_ productID: String, in services: NookServices) async {
        guard busy == .none else { return }
        busy = .buyingPack(productID)
        message = nil
        defer { busy = .none }
        switch await services.credits.purchase(productID) {
        case .credited(let pictures, let balance):
            credits = balance
            message = .creditsAdded(pictures)
        case .awaitingCredit:
            message = .creditsAwaiting
        case .pending:
            message = .packPending
        case .cancelled:
            break
        case .failed(let problem):
            message = .problem(problem)
        }
    }

    func purchase(in services: NookServices) async {
        guard busy == .none else { return }
        busy = .purchasing
        message = nil
        defer { busy = .none }
        switch await services.subscriptions.purchase() {
        case .purchased(let status):
            self.status = status
            message = .started
        case .pending:
            message = .pending
        case .cancelled:
            break
        case .failed(let problem):
            message = .problem(problem)
        }
    }

    func restore(in services: NookServices) async {
        guard busy == .none else { return }
        busy = .restoring
        message = nil
        defer { busy = .none }
        do {
            status = try await services.subscriptions.restore()
            message = status.hasStylingAccess(at: now()) ? .restored : .nothingToRestore
        } catch {
            message = .problem(error)
        }
    }
}
