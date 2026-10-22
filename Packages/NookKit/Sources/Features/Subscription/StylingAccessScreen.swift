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
    @State private var page: WebsiteLink?

    var body: some View {
        StylingAccessPage(
            model: model,
            actions: StylingAccessActions(
                subscribe: { Task { await model.purchase(in: services) } },
                restore: { Task { await model.restore(in: services) } },
                manage: { showsManage = true },
                open: { page = $0 }
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
        .fullScreenCover(item: $page) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        .task { await model.load(from: services) }
        .task { await model.follow(services) }
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

extension View {
    /// Apple's Manage subscription sheet, for other screens that link to it (Delete my account).
    func nookManageSubscriptionsSheet(isPresented: Binding<Bool>, groupID: String?) -> some View {
        modifier(ManageSubscriptionsSheet(isPresented: isPresented, groupID: groupID))
    }
}
