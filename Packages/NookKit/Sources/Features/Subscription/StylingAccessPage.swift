import DesignSystem
import Models
import SwiftUI

/// What Styling access's buttons do. The screen fills these in; snapshot tests leave them empty.
struct StylingAccessActions {
    var subscribe: () -> Void = {}
    var restore: () -> Void = {}
    var manage: () -> Void = {}
    var open: (WebsiteLink) -> Void = { _ in }
    /// 30b: Apple's offer code sheet.
    var redeem: () -> Void = {}
    /// 30b: buys a picture pack by its product ID.
    var buyPack: (String) -> Void = { _ in }
}

/// Styling access, top to bottom (`access.html`, `paywall.html`, Phase 30a):
///
/// 1. Her subscription, when she has or had one: free month, subscribed, a payment problem,
///    ended or refunded, with when it ends or renews.
/// 2. When she has no access: the offer from the App Store (the free month only if this Apple
///    Account can still have it), the day of the first charge, how to cancel, and Subscribe.
/// 3. What's included, with the allowances, and what's always free.
/// 4. Restore purchases, Manage subscription, Terms of use and Privacy policy.
///
/// 30b: the complimentary unlock first when she has it, her picture credits next to the try-on
/// allowance, the picture packs while they're sold, and Redeem a code (Apple's own sheet).
///
/// A custom page rather than StoreKit's `SubscriptionStoreView`: it says the allowances and what
/// stays free in the app's own words and design, the try-on and Help screens share its state,
/// and snapshot and UI tests can draw it from a fake. The App Store's own sheet still confirms
/// every purchase, and Manage subscription is Apple's sheet.
struct StylingAccessPage: View {
    let model: StylingAccessModel
    var allowances = StylingAllowances.placeholder
    var actions = StylingAccessActions()

    @Environment(\.calendar) private var calendar

    var body: some View {
        SettingsPage(header: SettingsHeader(title: StylingAccessText.title, lede: StylingAccessText.lede)) {
            if let message = model.message {
                NookBanner(
                    StylingAccessText.message(message), systemImage: icon(for: message), tone: tone(for: message)
                )
                .accessibilityIdentifier("access.message")
            }
            if model.isLoading {
                NookLoadingState(StylingAccessText.loading)
                    .floorCard()
            } else if model.cloudUnavailable {
                // 32b (L9): no backend in this build, so no offer, no packs and no restore.
                CloudUnavailableNote(message: StylingAccessText.unavailable)
                    .floorCard()
                SettingsGroup(header: StylingAccessText.freeHeader) {
                    SettingsNote(StylingAccessText.freeDetail)
                }
            } else {
                if model.isComplimentary {
                    complimentary
                }
                if model.state != .none {
                    yourSubscription
                }
                if model.showsOffer {
                    offer
                }
                included
                if model.showsPacks {
                    packs
                }
                SettingsGroup(header: StylingAccessText.freeHeader) {
                    SettingsNote(StylingAccessText.freeDetail)
                }
                links
            }
        }
    }

    // MARK: Groups

    /// 30b: the complimentary unlock.
    private var complimentary: some View {
        SettingsGroup(header: StylingAccessText.yourAccessHeader, identifier: "access.complimentary") {
            NookRow(
                StylingAccessText.complimentaryTitle, subtitle: StylingAccessText.complimentaryDetail,
                systemImage: "gift")
            if model.subscriptionStillBills {
                SettingsNote(StylingAccessText.complimentaryAndSubscription)
            }
        }
    }

    /// 30b: picture packs, one button each, with the App Store's price.
    private var packs: some View {
        SettingsGroup(header: StylingAccessText.packsHeader, identifier: "access.packs") {
            ForEach(model.packs) { pack in
                let buying = model.busy == .buyingPack(pack.productID)
                NookButton(
                    buying ? StylingAccessText.buyingPack : StylingAccessText.packButton(pack),
                    systemImage: "camera", kind: .soft, isLoading: buying, fillsWidth: true,
                    action: { actions.buyPack(pack.productID) }
                )
                .accessibilityHint(StylingAccessText.subscribeHint)
                .accessibilityIdentifier("access.pack.\(pack.pictures)")
                .padding(.horizontal, NookSpacing.small)
                .padding(.vertical, NookSpacing.xSmall)
            }
            SettingsNote(StylingAccessText.packsNote)
        }
    }

    private var yourSubscription: some View {
        SettingsGroup(header: StylingAccessText.yourSubscriptionHeader, identifier: "access.status") {
            NookRow(
                StylingAccessText.statusTitle(model.state),
                subtitle: StylingAccessText.statusDetail(
                    model.status, state: model.state, price: model.offer?.displayPrice),
                systemImage: statusImage)
        }
    }

    @ViewBuilder private var offer: some View {
        if let offer = model.offer {
            SettingsGroup(header: StylingAccessText.offerHeader, identifier: "access.offer") {
                VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                    Text(StylingAccessText.offerTitle(offer))
                        .nookTextStyle(.headline)
                        .foregroundStyle(.nook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(StylingAccessText.offerDetail(offer))
                        .nookTextStyle(.body)
                        .foregroundStyle(.nook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NookSpacing.medium)
                .padding(.vertical, NookSpacing.xSmall)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("access.offerTerms")

                let firstCharge = offer.firstCharge(startingAt: model.now(), calendar: calendar)
                if offer.freeTrial != nil {
                    NookRow(StylingAccessText.today, subtitle: StylingAccessText.todayDetail, systemImage: "sparkles")
                    NookRow(
                        StylingAccessText.firstCharge(firstCharge),
                        subtitle: StylingAccessText.firstChargeDetail(offer), systemImage: "calendar")
                    SettingsNote(StylingAccessText.cancelBefore(firstCharge))
                } else {
                    SettingsNote(StylingAccessText.cancelAnyTime)
                }
                NookButton(
                    model.busy == .purchasing ? StylingAccessText.purchasing : StylingAccessText.subscribeButton(offer),
                    systemImage: "sparkles", isLoading: model.busy == .purchasing, fillsWidth: true,
                    action: actions.subscribe
                )
                .accessibilityHint(StylingAccessText.subscribeHint)
                .accessibilityIdentifier("access.subscribe")
                .padding(.horizontal, NookSpacing.small)
                .padding(.vertical, NookSpacing.xSmall)
            }
        } else if model.offerProblem != nil {
            SettingsGroup(header: StylingAccessText.offerHeader, identifier: "access.offer") {
                SettingsNote(StylingAccessText.offerUnavailable)
            }
        }
    }

    private var included: some View {
        SettingsGroup(header: StylingAccessText.includedHeader, identifier: "access.included") {
            SettingsInfoRow(
                title: StylingAccessText.styleMe, detail: StylingAccessText.styleMeAllowance(allowances.styleMePerDay),
                systemImage: "sparkles")
            SettingsInfoRow(
                title: StylingAccessText.swapsAndQuestions,
                detail: StylingAccessText.swapsAllowance(allowances.swapsAndQuestionsPerDay),
                systemImage: "arrow.left.arrow.right")
            SettingsInfoRow(
                title: StylingAccessText.tryOn, detail: StylingAccessText.tryOnAllowance(allowances.tryOnPerMonth),
                systemImage: "camera")
            if model.showsCredits, let credits = model.credits {
                SettingsInfoRow(
                    title: StylingAccessText.creditsTitle, detail: StylingAccessText.creditsDetail(credits),
                    systemImage: "photo.stack"
                )
                .accessibilityIdentifier("access.credits")
            }
            SettingsNote(StylingAccessText.notUnlimited)
        }
    }

    private var links: some View {
        SettingsGroup {
            row(
                StylingAccessText.restore, value: model.busy == .restoring ? StylingAccessText.restoring : nil,
                systemImage: "arrow.clockwise", identifier: "access.restore", action: actions.restore)
            if model.showsRedeem {
                row(
                    StylingAccessText.redeem, subtitle: StylingAccessText.redeemDetail, systemImage: "giftcard",
                    identifier: "access.redeem", action: actions.redeem)
            }
            if model.showsManage {
                row(
                    StylingAccessText.manage, subtitle: StylingAccessText.manageDetail, systemImage: "creditcard",
                    identifier: "access.manage", action: actions.manage)
            }
            row(
                StylingAccessText.terms, systemImage: "doc.text", identifier: "access.terms",
                action: { actions.open(.terms) })
            row(
                StylingAccessText.privacy, systemImage: "lock", identifier: "access.privacy",
                action: { actions.open(.privacyPolicy) })
        }
    }

    private func row(
        _ title: String, subtitle: String? = nil, value: String? = nil, systemImage: String, identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            NookRow(title, subtitle: subtitle, value: value, systemImage: systemImage, accessory: .chevron)
        }
        .buttonStyle(.nookRow)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Looks

    private var statusImage: String {
        switch model.state {
        case .trial, .active: "checkmark.circle"
        case .gracePeriod, .billingRetry: "exclamationmark.triangle"
        case .none, .expired, .revoked: "circle"
        }
    }

    private func icon(for message: StylingAccessModel.Message) -> String {
        switch message {
        case .started, .restored, .redeemed, .creditsAdded: "checkmark.circle"
        case .pending, .packPending, .creditsAwaiting: "hourglass"
        case .nothingToRestore, .problem: "exclamationmark.triangle"
        }
    }

    private func tone(for message: StylingAccessModel.Message) -> NookBannerTone {
        switch message {
        case .started, .restored, .pending, .redeemed, .creditsAdded, .creditsAwaiting, .packPending: .neutral
        case .nothingToRestore, .problem: .warning
        }
    }
}
