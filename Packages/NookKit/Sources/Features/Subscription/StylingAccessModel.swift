import Foundation
import Models
import Observation

/// Styling access (Phase 30a, `access.html` and `paywall.html`): her subscription as StoreKit
/// reports it, the offer when she has none, and buying and restoring. The screen shows it; the
/// App Store's own sheet confirms every purchase.
@Observable
final class StylingAccessModel {
    enum Busy: Equatable {
        case none
        case purchasing
        case restoring
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
    var showsOffer: Bool { !hasAccess && state != .billingRetry }

    /// Whether there's a subscription for Manage subscription to show.
    var showsManage: Bool { state != .none }

    /// Shows a fixed state, for snapshot tests.
    func show(status: SubscriptionStatus, offer: SubscriptionOffer?, offerProblem: SubscriptionProblem? = nil) {
        self.status = status
        self.offer = offer
        self.offerProblem = offerProblem
        isLoading = false
    }

    /// The cached status at once, then StoreKit's, and the offer.
    func load(from services: NookServices) async {
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
        isLoading = false
    }

    /// Follows StoreKit's changes while the screen is open: a renewal, a refund, an approved Ask
    /// to Buy.
    func follow(_ services: NookServices) async {
        for await update in await services.subscriptions.statusUpdates() {
            let hadAccess = hasAccess
            status = update
            if !hadAccess, hasAccess, busy == .none, message == .pending { message = .started }
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
