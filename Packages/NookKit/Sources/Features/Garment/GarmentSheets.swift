import DesignSystem
import SwiftUI

/// What "Style with this" leads to (amendment, decision 2): Style Me with the piece as the
/// starting piece, or Make your own look starting from it (LR-08.3).
nonisolated enum StyleWithThisChoice: Hashable, Sendable {
    case styleMe
    case makeYourOwnLook
}

/// The two choices behind Style with this, as rows in a sheet.
struct StyleWithThisChoices: View {
    let choose: (StyleWithThisChoice) -> Void

    var body: some View {
        VStack(spacing: NookSpacing.xSmall) {
            choice(
                String(localized: "Style me with it", bundle: .module, comment: "Style with this choice"),
                subtitle: String(
                    localized: "Style Me builds an outfit around it.", bundle: .module,
                    comment: "Style with this choice: what Style me with it does"),
                systemImage: "sparkles", identifier: "styleMe", value: .styleMe)
            choice(
                String(localized: "Make my own look", bundle: .module, comment: "Style with this choice (LR-08)"),
                subtitle: String(
                    localized: "Build an outfit yourself, piece by piece, starting with it.", bundle: .module,
                    comment: "Style with this choice: what Make my own look does"),
                systemImage: "square.stack", identifier: "makeYourOwnLook", value: .makeYourOwnLook)
        }
    }

    private func choice(
        _ title: String, subtitle: String, systemImage: String, identifier: String, value: StyleWithThisChoice
    ) -> some View {
        Button {
            choose(value)
        } label: {
            NookRow(title, subtitle: subtitle, systemImage: systemImage, accessory: .chevron)
        }
        .buttonStyle(.nookRow)
        .accessibilityIdentifier("styleWithThis.\(identifier)")
    }
}

/// The Remove from closet sheet (LR-16): two choices, and both ask first.
///
/// - "I don't have it any more": it leaves Closet, suitcases and styling and stays in her
///   history. Undo follows as a toast.
/// - "Delete it": it goes to Recently deleted for 30 days. Before she confirms, it lists the
///   saved looks it affects (LR-16.2).
///
/// Archive isn't offered (LR-16). Each step moves VoiceOver to its heading.
struct RemoveFromClosetChoices: View {
    enum Step: Hashable {
        case choose
        case confirmNoLongerOwned
        case confirmDelete
    }

    let name: String
    /// When Recently deleted would let it go, such as "Nov 13".
    let deadline: String
    let savedLookNames: [String]
    let isSaving: Bool
    let confirmNoLongerOwned: () -> Void
    let confirmDelete: () -> Void

    @State private var step: Step
    @AccessibilityFocusState private var headingFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.closetIsStillImage) private var isStillImage

    init(
        name: String,
        deadline: String,
        savedLookNames: [String],
        isSaving: Bool,
        step: Step = .choose,
        confirmNoLongerOwned: @escaping () -> Void,
        confirmDelete: @escaping () -> Void
    ) {
        self.name = name
        self.deadline = deadline
        self.savedLookNames = savedLookNames
        self.isSaving = isSaving
        self.confirmNoLongerOwned = confirmNoLongerOwned
        self.confirmDelete = confirmDelete
        _step = State(initialValue: step)
    }

    var body: some View {
        Group {
            switch step {
            case .choose: choices
            case .confirmNoLongerOwned: noLongerOwned
            case .confirmDelete: delete
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        .onChange(of: step) { headingFocused = true }
    }

    private var choices: some View {
        VStack(spacing: NookSpacing.xSmall) {
            Button {
                step = .confirmNoLongerOwned
            } label: {
                NookRow(
                    String(
                        localized: "I don’t have it any more", bundle: .module, comment: "Remove from closet choice"),
                    subtitle: String(
                        localized: "It leaves your closet, suitcases and styling. Your saved looks keep it.",
                        bundle: .module, comment: "Remove from closet: what I don't have it any more does"),
                    systemImage: "hand.wave", accessory: .chevron)
            }
            .buttonStyle(.nookRow)
            .accessibilityIdentifier("remove.noLongerOwned")
            Button {
                step = .confirmDelete
            } label: {
                NookRow(
                    String(localized: "Delete it", bundle: .module, comment: "Remove from closet choice"),
                    subtitle: String(
                        localized: "It goes to Recently deleted for 30 days. You can bring it back until then.",
                        bundle: .module, comment: "Remove from closet: what Delete it does"),
                    systemImage: "trash", accessory: .chevron)
            }
            .buttonStyle(.nookRow)
            .accessibilityIdentifier("remove.delete")
        }
    }

    private var noLongerOwned: some View {
        confirmation(
            heading: String(
                localized: "Take it out of your closet?", bundle: .module,
                comment: "Remove from closet: asks before I don't have it any more"),
            confirmTitle: String(
                localized: "Yes, I don’t have it", bundle: .module,
                comment: "Button: confirms I don't have it any more"),
            confirmImage: "hand.wave", identifier: "remove.noLongerOwned.confirm", confirm: confirmNoLongerOwned
        ) {
            paragraph(
                String(
                    localized:
                        "\(name) leaves your closet, your suitcases and Style Me. Saved looks keep it, marked “No longer in your closet”. You can undo this straight after.",
                    bundle: .module, comment: "Remove from closet: what happens with I don't have it any more"))
        }
    }

    private var delete: some View {
        confirmation(
            heading: String(
                localized: "Delete \(name)?", bundle: .module, comment: "Remove from closet: asks before Delete it"),
            confirmTitle: String(localized: "Delete it", bundle: .module, comment: "Button: confirms Delete it"),
            confirmImage: "trash", identifier: "remove.delete.confirm", confirm: confirmDelete
        ) {
            paragraph(
                String(
                    localized: "It stays in Recently deleted until \(deadline). After that it’s deleted for good.",
                    bundle: .module, comment: "Remove from closet: the Recently deleted deadline, such as Nov 13"))
            if savedLookNames.isEmpty {
                paragraph(
                    String(
                        localized: "No saved looks use it.", bundle: .module,
                        comment: "Remove from closet: Delete it affects no saved looks"))
            } else {
                paragraph(
                    String(
                        localized: "These saved looks use it. They’ll show it faded, with Swap it:", bundle: .module,
                        comment: "Remove from closet: before the saved looks Delete it affects (LR-16.2)"))
                VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                    ForEach(Array(savedLookNames.enumerated()), id: \.offset) { _, lookName in
                        Label {
                            Text(lookName)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "bookmark")
                                .foregroundStyle(.nook.accent)
                        }
                        .nookTextStyle(.label)
                        .foregroundStyle(.nook.textPrimary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("remove.affectedLooks")
            }
        }
    }

    private func confirmation<Details: View>(
        heading: String,
        confirmTitle: String,
        confirmImage: String,
        identifier: String,
        confirm: @escaping () -> Void,
        @ViewBuilder details: () -> Details
    ) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            let title = Text(heading)
                .nookTextStyle(.lookTitle)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            // ImageRenderer draws a focusable view as empty space, so still images skip it.
            if isStillImage {
                title
            } else {
                title.accessibilityFocused($headingFocused)
            }
            details()
            VStack(spacing: NookSpacing.small) {
                NookButton(
                    confirmTitle, systemImage: confirmImage, isLoading: isSaving, fillsWidth: true, action: confirm
                )
                .accessibilityIdentifier(identifier)
                NookButton(
                    String(localized: "Go back", bundle: .module, comment: "Button: back to the two choices"),
                    systemImage: "chevron.left", kind: .soft, fillsWidth: true
                ) {
                    step = .choose
                }
                .accessibilityIdentifier("remove.back")
            }
            .padding(.top, NookSpacing.small)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
