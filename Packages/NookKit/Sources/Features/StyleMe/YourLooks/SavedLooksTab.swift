import DesignSystem
import Models
import SwiftUI

/// The Saved tab (LR-06): looks she saved for this source and occasion, free to open. Unsaved
/// earlier results aren't listed (LR-06.4), and there's no Shuffle (LR-06.3).
struct SavedLooksTab: View {
    let model: YourLooksModel
    let text: YourLooksText
    let actions: YourLooksActions

    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(spacing: NookSpacing.medium) {
            if model.looksUnavailable {
                NookErrorState(
                    String(localized: "Saved looks didn’t load", bundle: .module, comment: "Saved tab error title"),
                    message: String(
                        localized: "Nothing was sent. Try again in a moment.", bundle: .module,
                        comment: "Your looks when the stores fail"),
                    retry: actions.reloadSaved)
            } else if model.savedLooks.isEmpty {
                NookEmptyState(text.savedEmptyTitle, message: text.savedEmptyMessage, systemImage: "heart")
                    .accessibilityIdentifier("results.saved.empty")
            } else {
                Text(text.savedLead)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: NookSpacing.xSmall) {
                    ForEach(model.savedLooks) { look in
                        row(look)
                    }
                }
            }
        }
    }

    private func row(_ look: Look) -> some View {
        let content = LookBundleContent(look: look, garments: model.garments)
        let name = look.name ?? text.name(for: look, garments: model.garments)
        let detail = detail(for: look, content: content)
        return Button {
            actions.openSaved(look)
        } label: {
            HStack(spacing: NookSpacing.medium) {
                LookBundle(content, size: LookBundleSize(width: 70), title: name)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                    Text(name)
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.textPrimary)
                    Text(detail)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.nook.chevron)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, NookSpacing.small)
            .padding(.vertical, NookSpacing.small)
        }
        .buttonStyle(.nookRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LookBundleText.summary(of: content, title: name, locale: locale)))
        .accessibilityValue(Text(detail))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("results.saved.\(look.id)")
    }

    /// "4 pieces · Last worn 9 Oct".
    private func detail(for look: Look, content: LookBundleContent) -> String {
        var parts = [StyleMeText.pieces(content.pieces.count)]
        if let lastWorn = look.lastWorn {
            parts.append(
                LastWornText.describe(lastWorn, now: model.request.createdAt, calendar: calendar, locale: locale))
        }
        return parts.joined(separator: " · ")
    }
}

/// A saved look opened from the Saved tab: its bundle and pieces. Look detail, Wear today and
/// renaming come with Saved Looks (Phase 12a).
struct SavedLookSheet: View {
    let look: Look
    let garments: [Garment.ID: Garment]
    let findOne: (LookBundlePiece) -> Void

    var body: some View {
        let content = LookBundleContent(look: look, garments: garments)
        VStack(spacing: NookSpacing.medium) {
            LookBundle(content, size: .large, title: look.name)
            LookPieceList(content: content, onFindOne: findOne)
        }
        .frame(maxWidth: .infinity)
    }
}

/// What a stand-in sheet on Your looks is about. Each one opens without sending anything.
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
