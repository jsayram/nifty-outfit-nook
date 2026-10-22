import DesignSystem
import Models
import StoreKit
import SwiftUI

/// Styling access (Phase 30a): pushed from Profile, or opened as a sheet where a feature needs
/// it (try-on, once its pictures cost something). See `StylingAccessPage`.
struct StylingAccessScreen: View {
    /// True when it's a sheet: then it has its own "Not now" button.
    var isSheet = false

    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var model = StylingAccessModel()
    @State private var showsManage = false
    @State private var showsRedeem = false
    @State private var page: WebsiteLink?

    var body: some View {
        StylingAccessPage(
            model: model,
            actions: StylingAccessActions(
                subscribe: { Task { await model.purchase(in: services) } },
                restore: { Task { await model.restore(in: services) } },
                manage: { showsManage = true },
                open: { page = $0 },
                redeem: { showsRedeem = true },
                buyPack: { id in Task { await model.buyPack(id, in: services) } }
            )
        )
        .navigationTitle(StylingAccessText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is on the wall, as on Profile.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button(StylingAccessText.close) { dismiss() }
                        .accessibilityIdentifier("access.close")
                }
            }
        }
        .modifier(ManageSubscriptionsSheet(isPresented: $showsManage, groupID: model.groupID))
        // 30b: Apple's own offer code sheet (Apple doesn't allow a custom one).
        .modifier(
            OfferCodeSheet(isPresented: $showsRedeem) {
                Task { await model.redeemed(in: services) }
            }
        )
        .fullScreenCover(item: $page) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        .task { await model.load(from: services) }
        .task { await model.follow(services) }
        .task { await model.followCredits(services) }
        // Back from Apple's sheet: she may have cancelled or changed how she pays.
        .onChange(of: showsManage) { _, isShown in
            if !isShown { Task { await model.load(from: services) } }
        }
    }
}

/// Apple's Manage subscription sheet, for the app's subscription group when StoreKit has told
/// the app its ID, otherwise for all her subscriptions.
private struct ManageSubscriptionsSheet: ViewModifier {
    @Binding var isPresented: Bool
    let groupID: String?

    func body(content: Content) -> some View {
        if let groupID {
            content.manageSubscriptionsSheet(isPresented: $isPresented, subscriptionGroupID: groupID)
        } else {
            content.manageSubscriptionsSheet(isPresented: $isPresented)
        }
    }
}

/// 30b: Apple's offer code sheet. On iOS 27 it hands back the redeemed transaction; before that the
/// transaction arrives through `Transaction.updates`. Either way the services finish it and read
/// the status again (`redeemedOfferCode()`), so `done` only has to say the sheet closed with a
/// redemption. A failure or a sheet closed without a code says nothing.
private struct OfferCodeSheet: ViewModifier {
    @Binding var isPresented: Bool
    let done: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.offerCodeRedemption(options: [], isPresented: $isPresented) { result in
                if case .success = result { done() }
            }
        } else {
            content.offerCodeRedemption(isPresented: $isPresented) { result in
                if case .success = result { done() }
            }
        }
    }
}

extension View {
    /// Apple's Manage subscription sheet, for other screens that link to it (Delete my account).
    func nookManageSubscriptionsSheet(isPresented: Binding<Bool>, groupID: String?) -> some View {
        modifier(ManageSubscriptionsSheet(isPresented: isPresented, groupID: groupID))
    }
}
