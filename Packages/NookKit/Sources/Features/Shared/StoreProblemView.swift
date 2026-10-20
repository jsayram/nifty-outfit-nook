import DesignSystem
import Models
import SwiftUI

/// What shows when the store on the iPhone couldn't be opened (Phase 21a), instead of onboarding
/// or the tabs. The words come from `docs/decisions/0004-backup-and-recovery.md`, section 7.
/// Nothing was reset or deleted, and the app changes nothing while this shows. The buttons that
/// design adds (Try again, Export a copy, Send feedback) come with Phase 21b.
struct StoreProblemView: View {
    let problem: StoreOpenProblem

    var body: some View {
        ScrollView(.vertical) {
            NookEmptyState(
                StoreProblemText.title(problem), message: StoreProblemText.message(problem),
                systemImage: "externaldrive.badge.exclamationmark"
            )
            .padding(.horizontal, NookSpacing.screenMargin)
            .padding(.top, NookSpacing.xxxLarge)
            .accessibilityIdentifier("storeProblem")
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
    }
}

/// The recovery screen's words.
enum StoreProblemText {
    static func title(_ problem: StoreOpenProblem) -> String {
        switch problem {
        case .newerVersion:
            String(
                localized: "This closet was saved by a newer version", bundle: .module,
                comment: "Recovery screen title: the store is from a newer app version")
        case .notEnoughSpace:
            String(
                localized: "Your closet needs more space to update", bundle: .module,
                comment: "Recovery screen title: not enough free space for the update's safety copy")
        case .updateFailed:
            String(
                localized: "Your closet couldn’t be updated", bundle: .module,
                comment: "Recovery screen title: the store's update failed")
        case .couldNotOpen:
            String(
                localized: "Your closet didn’t open", bundle: .module,
                comment: "Recovery screen title: the store couldn't be opened")
        }
    }

    static func message(_ problem: StoreOpenProblem) -> String {
        switch problem {
        case .newerVersion:
            String(
                localized: "Update Nifty Outfit Nook to open it. Nothing was changed or deleted.", bundle: .module,
                comment: "Recovery screen: the store is from a newer app version")
        case .notEnoughSpace:
            String(
                localized: "Nothing is lost. Free up some space on this iPhone, then open the app again.",
                bundle: .module, comment: "Recovery screen: not enough free space")
        case .updateFailed:
            String(
                localized: "Nothing is lost. The copy from before the update is safe on this iPhone.",
                bundle: .module, comment: "Recovery screen: the store's update failed")
        case .couldNotOpen:
            String(
                localized: "Nothing was deleted. Close the app and open it again.", bundle: .module,
                comment: "Recovery screen: the store couldn't be opened")
        }
    }
}
