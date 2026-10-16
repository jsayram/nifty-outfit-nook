import DesignSystem
import Models
import SwiftUI

/// What a stand-in sheet is about: Ask stylist and Find one (later phases), and a saved look
/// opened from Your looks' Saved tab. Your looks, look detail and Swap a piece show them. Each
/// one opens without sending anything.
enum ResultStub: Identifiable, Hashable {
    /// Ask stylist (FR-14): later.
    case askStylist(Look.ID)
    /// Find one on a piece she doesn't own (LR-05b.4): Phase 34. Nothing is searched.
    case findOne(pieceName: String)
    /// A saved look from the Saved tab.
    case saved(Look.ID)

    var id: Self { self }

    var title: String {
        switch self {
        case .askStylist: String(localized: "Ask stylist", bundle: .module, comment: "Results button (RD-06)")
        case .findOne:
            String(localized: "Find one", bundle: .module, comment: "Button on a look's piece she doesn't own")
        case .saved: String(localized: "Saved look", bundle: .module, comment: "Sheet title for a saved look")
        }
    }

    var subtitle: String? {
        switch self {
        case .findOne(let name): name
        case .askStylist, .saved: nil
        }
    }

    var systemImage: String {
        switch self {
        case .askStylist: "bubble.left.and.bubble.right"
        case .findOne: "magnifyingglass"
        case .saved: "heart"
        }
    }

    var heading: String {
        switch self {
        case .askStylist:
            String(localized: "Ask stylist comes later", bundle: .module, comment: "Ask stylist stand-in")
        case .findOne:
            String(localized: "Shopping comes later", bundle: .module, comment: "Find one stand-in")
        case .saved:
            ""
        }
    }

    var message: String {
        switch self {
        case .askStylist:
            String(
                localized: "You’ll be able to ask about this look in your own words.", bundle: .module,
                comment: "Ask stylist stand-in")
        case .findOne:
            String(
                localized: "Finding a piece like this comes in a later version. Nothing was searched.",
                bundle: .module, comment: "Find one stand-in (LR-05b.4)")
        case .saved:
            ""
        }
    }

    var identifier: String {
        switch self {
        case .askStylist: "askStylist"
        case .findOne: "findOne"
        case .saved: "saved"
        }
    }
}

/// The body of a stand-in sheet: what's coming, in plain words.
struct ResultStubContent: View {
    let stub: ResultStub

    var body: some View {
        NookEmptyState(stub.heading, message: stub.message, systemImage: stub.systemImage)
            .accessibilityIdentifier("results.stub.\(stub.identifier)")
    }
}
