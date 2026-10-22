import Foundation
import Models

/// The words on Styling access and the paywall (Phase 30a). Plain and exact, as App Review
/// Guideline 3.1.2 asks: the price and period from the App Store, what the free month is, when
/// the first charge comes, that it renews until she cancels, and how to cancel. No prices or
/// dates are typed here; they come from StoreKit.
nonisolated enum StylingAccessText {
    static var title: String {
        String(localized: "Styling access", bundle: .module, comment: "Styling access: screen title and Profile row")
    }

    static var lede: String {
        String(
            localized:
                "Style Me, swaps, Ask stylist and try-on pictures use styling access. Your closet stays free.",
            bundle: .module, comment: "Styling access: the line under the title")
    }

    /// 32b (L9): this build has no backend settings.
    static var unavailable: String {
        String(
            localized:
                "Styling access and picture packs can’t be offered right now. Quick ideas and everything on your phone keep working.",
            bundle: .module, comment: "Styling access when this build has no backend (nothing can be bought)")
    }

    static var loading: String {
        String(localized: "Checking with the App Store", bundle: .module, comment: "Styling access: loading")
    }

    // MARK: Profile row

    /// The value on Profile's Styling access row.
    static func rowValue(_ state: SubscriptionState, isComplimentary: Bool = false) -> String {
        if isComplimentary {
            return String(localized: "Complimentary", bundle: .module, comment: "Profile: Styling access row value")
        }
        return switch state {
        case .none:
            String(localized: "Not subscribed", bundle: .module, comment: "Profile: Styling access row value")
        case .trial:
            String(localized: "Free month", bundle: .module, comment: "Profile: Styling access row value")
        case .active:
            String(localized: "Subscribed", bundle: .module, comment: "Profile: Styling access row value")
        case .gracePeriod, .billingRetry:
            String(localized: "Payment problem", bundle: .module, comment: "Profile: Styling access row value")
        case .expired, .revoked:
            String(localized: "Ended", bundle: .module, comment: "Profile: Styling access row value")
        }
    }

    static var rowDetail: String {
        String(
            localized: "Style Me, swaps, Ask stylist and try-on pictures", bundle: .module,
            comment: "Profile: the line under the Styling access row")
    }

    // MARK: Her subscription

    static var yourSubscriptionHeader: String {
        String(localized: "Your subscription", bundle: .module, comment: "Styling access: section header")
    }

    static func statusTitle(_ state: SubscriptionState) -> String {
        switch state {
        case .none:
            String(localized: "Not subscribed", bundle: .module, comment: "Styling access: status")
        case .trial:
            String(localized: "Free month", bundle: .module, comment: "Styling access: status")
        case .active:
            String(localized: "Subscribed", bundle: .module, comment: "Styling access: status")
        case .gracePeriod, .billingRetry:
            String(localized: "Payment problem", bundle: .module, comment: "Styling access: status")
        case .expired:
            String(localized: "Subscription ended", bundle: .module, comment: "Styling access: status")
        case .revoked:
            String(localized: "Subscription refunded", bundle: .module, comment: "Styling access: status")
        }
    }

    /// The line under the status: when it ends or renews, and what happens next.
    static func statusDetail(_ status: SubscriptionStatus, state: SubscriptionState, price: String?) -> String {
        let end = status.expiresAt.map(day) ?? ""
        switch state {
        case .none:
            return lede
        case .trial:
            guard status.willAutoRenew else {
                return String(
                    localized: "Your free month ends \(end). You’ve cancelled, so nothing will be charged.",
                    bundle: .module, comment: "Styling access: trial, cancelled. The argument is a date.")
            }
            if let price {
                return String(
                    localized:
                        "Your free month ends \(end). Then \(price) a month, every month until you cancel.",
                    bundle: .module,
                    comment: "Styling access: trial. The arguments are a date and the App Store's price.")
            }
            return String(
                localized: "Your free month ends \(end). Then it renews monthly until you cancel.",
                bundle: .module, comment: "Styling access: trial, price unknown. The argument is a date.")
        case .active:
            guard status.willAutoRenew else {
                return String(
                    localized: "Ends \(end). It won’t renew, so nothing more will be charged.", bundle: .module,
                    comment: "Styling access: subscribed, cancelled. The argument is a date.")
            }
            if let price {
                return String(
                    localized: "Renews \(end) at \(price) a month.", bundle: .module,
                    comment: "Styling access: subscribed. The arguments are a date and the App Store's price.")
            }
            return String(
                localized: "Renews \(end).", bundle: .module,
                comment: "Styling access: subscribed, price unknown. The argument is a date.")
        case .gracePeriod:
            let until = (status.gracePeriodEndsAt ?? status.expiresAt).map(day) ?? ""
            return String(
                localized:
                    "Apple couldn’t take the last payment. Styling access stays on until \(until) while you update your payment details in Manage subscription.",
                bundle: .module, comment: "Styling access: billing grace period. The argument is a date.")
        case .billingRetry:
            return String(
                localized:
                    "Apple couldn’t take the last payment, so styling access is paused. Update your payment details in Manage subscription, and it starts again.",
                bundle: .module, comment: "Styling access: billing retry")
        case .expired:
            return String(
                localized: "Styling access is off. Your closet, looks and pictures are all still here.",
                bundle: .module, comment: "Styling access: subscription ended")
        case .revoked:
            return String(
                localized:
                    "Apple refunded this subscription, so styling access is off. Your closet, looks and pictures are all still here.",
                bundle: .module, comment: "Styling access: subscription refunded or revoked")
        }
    }

    // MARK: Complimentary access (30b)

    static var yourAccessHeader: String {
        String(localized: "Your access", bundle: .module, comment: "Styling access: section header, complimentary")
    }

    static var complimentaryTitle: String {
        String(localized: "Complimentary access", bundle: .module, comment: "Styling access: status")
    }

    static var complimentaryDetail: String {
        String(
            localized: "Styling access is on at no charge. It doesn’t renew and has no end date.", bundle: .module,
            comment: "Styling access: complimentary unlock")
    }

    static var complimentaryAndSubscription: String {
        String(
            localized:
                "You also have a subscription. Redeeming a code didn’t cancel it or refund earlier charges. To stop paying for it, cancel it in Manage subscription.",
            bundle: .module, comment: "Styling access: complimentary unlock while a subscription still renews")
    }

    static var redeem: String {
        String(localized: "Redeem a code", bundle: .module, comment: "Styling access: button")
    }

    static var redeemDetail: String {
        String(
            localized: "For an App Store offer code you were given", bundle: .module,
            comment: "Styling access: under Redeem a code")
    }

    // MARK: Picture credits (30b)

    static var creditsTitle: String {
        String(localized: "Picture credits", bundle: .module, comment: "Styling access: the credit balance row")
    }

    /// The balance: "12 left. They don't expire."
    static func creditsDetail(_ count: Int) -> String {
        String(
            localized: "\(count) left. Credits don’t expire, and work without a subscription.", bundle: .module,
            comment: "Styling access: credit balance. The argument is a number.")
    }

    static var packsHeader: String {
        String(localized: "Extra try-on pictures", bundle: .module, comment: "Styling access: section header")
    }

    static var packsNote: String {
        String(
            localized:
                "One-time purchases. Each picture uses 1 credit once the month’s included pictures are used. Credits don’t expire.",
            bundle: .module, comment: "Styling access: under the picture packs")
    }

    /// A pack's button: "10 pictures, $2.99".
    static func packButton(_ pack: CreditPackOffer) -> String {
        String(
            localized: "\(pack.pictures) pictures, \(pack.displayPrice)", bundle: .module,
            comment: "Styling access: buy a picture pack. The arguments are a number and the App Store's price.")
    }

    static var buyingPack: String {
        String(localized: "Waiting for the App Store", bundle: .module, comment: "Styling access: while buying a pack")
    }

    // MARK: The offer

    static var offerHeader: String {
        String(localized: "Subscribe", bundle: .module, comment: "Styling access: section header over the offer")
    }

    /// The offer in one line: "1 month free, then $9.99 a month." or "$9.99 a month."
    static func offerTitle(_ offer: SubscriptionOffer) -> String {
        if let trial = offer.freeTrial {
            return String(
                localized: "\(length(trial)) free, then \(offer.displayPrice) a month.", bundle: .module,
                comment: "Paywall: the offer. The arguments are the trial's length, like 1 month, and the price.")
        }
        return String(
            localized: "\(offer.displayPrice) a month.", bundle: .module,
            comment: "Paywall: the offer with no free trial. The argument is the App Store's price.")
    }

    static func offerDetail(_ offer: SubscriptionOffer) -> String {
        if offer.freeTrial != nil {
            return String(
                localized: "Nothing is charged today. It renews automatically every month until you cancel.",
                bundle: .module, comment: "Paywall: under the offer, with a free month")
        }
        return String(
            localized:
                "Charged today, then every month until you cancel. This Apple Account has already had its free month.",
            bundle: .module, comment: "Paywall: under the offer, without a free month")
    }

    static var today: String {
        String(localized: "Today", bundle: .module, comment: "Paywall: the first step of the timeline")
    }

    static var todayDetail: String {
        String(
            localized: "Styling access starts. Nothing is charged.", bundle: .module,
            comment: "Paywall: what happens today, with a free month")
    }

    static func firstCharge(_ date: Date) -> String {
        String(
            localized: "\(day(date)), first charge", bundle: .module,
            comment: "Paywall: the second step of the timeline. The argument is a date.")
    }

    static func firstChargeDetail(_ offer: SubscriptionOffer) -> String {
        String(
            localized: "\(offer.displayPrice), then every month until you cancel.", bundle: .module,
            comment: "Paywall: the first charge. The argument is the App Store's price.")
    }

    static func cancelBefore(_ date: Date) -> String {
        String(
            localized:
                "To pay nothing, cancel at least a day before \(day(date)): Settings, then your name, then Subscriptions.",
            bundle: .module, comment: "Paywall: how to cancel the free month. The argument is a date.")
    }

    static var cancelAnyTime: String {
        String(
            localized:
                "Cancel at least a day before it renews: Settings, then your name, then Subscriptions. You keep styling access until the end of the month you’ve paid for.",
            bundle: .module, comment: "Paywall: how to cancel, without a free month")
    }

    static func subscribeButton(_ offer: SubscriptionOffer) -> String {
        if offer.freeTrial != nil {
            return String(localized: "Start free month", bundle: .module, comment: "Paywall: the purchase button")
        }
        return String(
            localized: "Subscribe for \(offer.displayPrice) a month", bundle: .module,
            comment: "Paywall: the purchase button without a free month. The argument is the price.")
    }

    static var subscribeHint: String {
        String(
            localized: "Opens the App Store to confirm.", bundle: .module,
            comment: "Paywall: VoiceOver hint on the purchase button")
    }

    static var purchasing: String {
        String(localized: "Waiting for the App Store", bundle: .module, comment: "Paywall: while buying")
    }

    static var offerUnavailable: String {
        String(
            localized: "The App Store didn’t answer, so the price can’t be shown. Try again later.",
            bundle: .module, comment: "Paywall: the offer couldn't be loaded")
    }

    // MARK: What's included

    static var includedHeader: String {
        String(localized: "What’s included", bundle: .module, comment: "Paywall: section header")
    }

    static var styleMe: String {
        String(localized: "Style Me", bundle: .module, comment: "Paywall: an included feature")
    }

    static func styleMeAllowance(_ count: Int) -> String {
        String(
            localized: "Up to \(count) requests a day", bundle: .module,
            comment: "Paywall: Style Me's allowance. The argument is a number.")
    }

    static var swapsAndQuestions: String {
        String(localized: "Swap a piece and Ask stylist", bundle: .module, comment: "Paywall: an included feature")
    }

    static func swapsAllowance(_ count: Int) -> String {
        String(
            localized: "Up to \(count) a day", bundle: .module,
            comment: "Paywall: the allowance for swaps and questions. The argument is a number.")
    }

    static var tryOn: String {
        String(localized: "Try-on pictures", bundle: .module, comment: "Paywall: an included feature")
    }

    static func tryOnAllowance(_ count: Int) -> String {
        String(
            localized: "Up to \(count) a month. Reopening one is free.", bundle: .module,
            comment: "Paywall: the try-on allowance. The argument is a number.")
    }

    static var notUnlimited: String {
        String(
            localized: "Styling isn’t unlimited. When an allowance is used up, the app says when more comes back.",
            bundle: .module, comment: "Paywall: under the included features")
    }

    // MARK: Always free

    static var freeHeader: String {
        String(localized: "Always free", bundle: .module, comment: "Paywall: section header")
    }

    static var freeDetail: String {
        String(
            localized:
                "Your closet, laundry, suitcases, saved looks, search and the looks you make yourself work without a subscription, and keep working if it ends.",
            bundle: .module, comment: "Paywall: what stays free")
    }

    // MARK: Actions

    static var restore: String {
        String(localized: "Restore purchases", bundle: .module, comment: "Styling access: button")
    }

    static var restoring: String {
        String(localized: "Restoring", bundle: .module, comment: "Styling access: while restoring")
    }

    static var manage: String {
        String(localized: "Manage subscription", bundle: .module, comment: "Styling access: button")
    }

    static var manageDetail: String {
        String(
            localized: "Cancel, or update how you pay, with Apple", bundle: .module,
            comment: "Styling access: under Manage subscription")
    }

    static var terms: String {
        String(localized: "Terms of use", bundle: .module, comment: "Styling access: a link")
    }

    static var privacy: String {
        String(localized: "Privacy policy", bundle: .module, comment: "Styling access: a link")
    }

    static var close: String {
        String(localized: "Not now", bundle: .module, comment: "Paywall: closes the sheet")
    }

    // MARK: Messages

    static func message(_ message: StylingAccessModel.Message) -> String {
        switch message {
        case .pending:
            String(
                localized: "Waiting for approval. When it’s approved, styling access starts on its own.",
                bundle: .module, comment: "Paywall: Ask to Buy or another approval")
        case .started:
            String(localized: "Styling access is on.", bundle: .module, comment: "Paywall: after buying")
        case .restored:
            String(localized: "Your subscription is restored.", bundle: .module, comment: "Styling access: restored")
        case .nothingToRestore:
            String(
                localized: "No active subscription was found for this Apple Account.", bundle: .module,
                comment: "Styling access: restore found nothing")
        case .redeemed:
            String(
                localized: "Your code is redeemed. Styling access is on.", bundle: .module,
                comment: "Styling access: after redeeming an offer code")
        case .creditsAdded(let count):
            String(
                localized: "\(count) picture credits added.", bundle: .module,
                comment: "Styling access: after buying a pack. The argument is a number. Pluralized.")
        case .creditsAwaiting:
            String(
                localized:
                    "Your purchase went through. The pictures will be added when the app can reach the server. Nothing more will be charged.",
                bundle: .module, comment: "Styling access: pack bought but not credited yet")
        case .packPending:
            String(
                localized: "Waiting for approval. When it’s approved, the pictures are added on their own.",
                bundle: .module, comment: "Styling access: pack waiting for Ask to Buy")
        case .problem(let problem):
            switch problem {
            case .offline:
                String(
                    localized: "The App Store can’t be reached. Check your connection and try again.",
                    bundle: .module, comment: "Styling access: offline")
            case .notAllowed:
                String(
                    localized: "Purchases are turned off on this iPhone in Screen Time.", bundle: .module,
                    comment: "Styling access: purchases not allowed")
            case .unavailable:
                String(
                    localized: "The subscription isn’t available right now. Nothing was charged.",
                    bundle: .module, comment: "Styling access: product unavailable")
            case .unverified, .failed:
                String(
                    localized: "That didn’t work, and nothing was charged. Try again.", bundle: .module,
                    comment: "Styling access: purchase failed")
            }
        }
    }

    // MARK: Formatting

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide))
    }

    /// "1 month", "2 weeks", from StoreKit's period.
    static func length(_ period: SubscriptionPeriod) -> String {
        let count = period.value
        return switch period.unit {
        case .day:
            String(localized: "\(count) days", bundle: .module, comment: "A length of time. Pluralized.")
        case .week:
            String(localized: "\(count) weeks", bundle: .module, comment: "A length of time. Pluralized.")
        case .month:
            String(localized: "\(count) months", bundle: .module, comment: "A length of time. Pluralized.")
        case .year:
            String(localized: "\(count) years", bundle: .module, comment: "A length of time. Pluralized.")
        }
    }
}
