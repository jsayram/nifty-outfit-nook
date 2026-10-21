import DesignSystem
import SwiftUI

/// The short sheet the faded hamper opens while laundry tracking is off (RD-11,
/// `screens/laundry-off.html`). It explains tracking once, offers Turn on and points to the
/// Profile switch. Nothing in it nags: Not now just closes it.
struct LaundryTrackingSheet: View {
    /// Pieces still marked as in the wash from before, kept while tracking is off.
    let keptDirtyCount: Int
    /// Turns tracking on. Returns false if it couldn't be saved.
    let turnOn: () async -> Bool
    /// Closes the sheet and opens Profile, where the switch lives.
    let openProfile: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var saveFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            Text(
                "Laundry tracking keeps note of what’s in the wash, so Style Me doesn’t suggest it.",
                bundle: .module, comment: "Laundry tracking sheet: what tracking does"
            )
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: NookSpacing.medium) {
                point(
                    systemImage: "washer",
                    title: String(localized: "When it’s on", bundle: .module, comment: "Laundry tracking sheet"),
                    text: String(
                        localized: "You mark pieces as in the wash. Style Me skips them unless you allow one.",
                        bundle: .module, comment: "Laundry tracking sheet"))
                point(
                    systemImage: "checkmark",
                    title: String(localized: "While it’s off", bundle: .module, comment: "Laundry tracking sheet"),
                    text: String(
                        localized: "Every piece counts as available.", bundle: .module,
                        comment: "Laundry tracking sheet"))
                point(
                    systemImage: "basket",
                    title: String(localized: "Nothing is erased", bundle: .module, comment: "Laundry tracking sheet"),
                    text: keptText)
            }

            if saveFailed {
                Label {
                    Text(
                        "Couldn’t turn it on. Try again.", bundle: .module,
                        comment: "Laundry tracking sheet: saving the setting failed")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .nookTextStyle(.note)
                .foregroundStyle(.nook.error)
            }

            NookAdaptiveStack {
                NookButton(
                    String(localized: "Turn on", bundle: .module, comment: "Button: turns laundry tracking on"),
                    isLoading: isSaving, fillsWidth: true
                ) {
                    Task { await save() }
                }
                .accessibilityIdentifier("laundryTracking.turnOn")
                NookButton(
                    String(
                        localized: "Not now", bundle: .module,
                        comment:
                            "Button: closes a question without doing anything, as on the laundry tracking sheet and Remember this name"
                    ),
                    kind: .soft, fillsWidth: true
                ) {
                    dismiss()
                }
            }

            Button(action: openProfile) {
                HStack(spacing: NookSpacing.xSmall) {
                    Text(
                        "You can change this in Profile", bundle: .module,
                        comment: "Link from the laundry tracking sheet to the Profile switch")
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.nook(.text))
            .accessibilityIdentifier("laundryTracking.profile")
        }
    }

    private var keptText: String {
        guard keptDirtyCount > 0 else {
            return String(
                localized: "Pieces you mark stay marked while it’s off.", bundle: .module,
                comment: "Laundry tracking sheet, when nothing is marked as in the wash")
        }
        return String(
            localized:
                "Your \(keptDirtyCount) pieces marked as in the wash are kept. Turn it back on and they come back.",
            bundle: .module,
            comment: "Laundry tracking sheet: how many pieces are still marked as in the wash")
    }

    private func point(systemImage: String, title: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NookSpacing.medium) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.nook.accent)
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                Text(title)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textPrimary)
                Text(text)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func save() async {
        isSaving = true
        saveFailed = false
        let saved = await turnOn()
        isSaving = false
        if saved {
            dismiss()
        } else {
            saveFailed = true
        }
    }
}
