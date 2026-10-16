import DesignSystem
import Models
import SwiftUI

/// "Continue where you left off?" with Resume and Discard (PRD §7.3, FR-31): a piece she
/// started adding or editing and didn't save. Shown on the Add a piece or Edit form when she
/// opens it again, and at the top of Closet.
struct DraftResumeCard: View {
    let draft: GarmentDraft
    let now: Date
    /// Identifier prefix for UI tests: `draft` on the form, `closet.draft` on Closet.
    let identifier: String
    let resume: () -> Void
    let discard: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Text("Continue where you left off?", bundle: .module, comment: "Draft card title (PRD 7.3)")
                .nookTextStyle(.lookTitle)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(DraftResumeText.message(for: draft))
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(identifier).message")
            Text(DraftResumeText.age(of: draft, now: now, locale: locale))
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NookAdaptiveStack(spacing: NookSpacing.small) {
                NookButton(
                    String(localized: "Resume", bundle: .module, comment: "Button: carries on with a draft"),
                    systemImage: "arrow.uturn.forward", fillsWidth: true, action: resume
                )
                .accessibilityIdentifier("\(identifier).resume")
                NookButton(
                    String(localized: "Discard", bundle: .module, comment: "Button: throws a draft away"),
                    systemImage: "trash", kind: .soft, fillsWidth: true, action: discard
                )
                .accessibilityHint(
                    Text(
                        "Throws away what you started. Your closet doesn’t change.", bundle: .module,
                        comment: "Hint on a draft's Discard")
                )
                .accessibilityIdentifier("\(identifier).discard")
            }
            .padding(.top, NookSpacing.xSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nookCard(.strong)
    }
}

/// The words on the draft card.
enum DraftResumeText {
    /// "Sage cardigan isn’t in your closet yet." or "Your changes to Navy dress pants aren’t
    /// saved yet."
    static func message(for draft: GarmentDraft) -> String {
        let name = draft.details.name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.target {
        case .newPiece:
            if name.isEmpty {
                return String(
                    localized: "The piece you started adding isn’t in your closet yet.", bundle: .module,
                    comment: "Draft card: a new piece with no name yet")
            }
            return String(
                localized: "\(name) isn’t in your closet yet.", bundle: .module,
                comment: "Draft card: a new piece, with the name she gave it")
        case .garment:
            let saved = draft.base.name.isEmpty ? name : draft.base.name
            return String(
                localized: "Your changes to \(saved) aren’t saved yet.", bundle: .module,
                comment: "Draft card: changes to a piece, with the piece's saved name")
        }
    }

    /// "Started 5 minutes ago".
    static func age(of draft: GarmentDraft, now: Date, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        let when =
            now.timeIntervalSince(draft.savedAt) < 60
            ? String(localized: "just now", bundle: .module, comment: "Draft card: changed less than a minute ago")
            : formatter.localizedString(for: draft.savedAt, relativeTo: now)
        return String(
            localized: "Last changed \(when)", bundle: .module,
            comment: "Draft card: when the draft last changed, like 5 minutes ago")
    }
}
