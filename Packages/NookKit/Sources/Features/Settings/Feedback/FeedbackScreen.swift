import DesignSystem
import Models
import SwiftUI

/// Send feedback (RD-10, `feedback.html`): the middle desk drawer, also on Profile and at the end
/// of Help. See `FeedbackModel` for what's sent and how.
struct FeedbackScreen: View {
    /// The note kept at the root, so a half-written one waits for her (`nil` in previews).
    @Environment(\.feedbackDraft) private var shared
    @State private var local = FeedbackModel()
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focus: FeedbackField?

    private var model: FeedbackModel { shared ?? local }

    var body: some View {
        FeedbackPage(
            model: model,
            focus: $focus,
            send: {
                if !model.send() { focus = .message }
            },
            done: {
                model.startOver()
                dismiss()
            },
            writeAnother: { model.startOver() }
        )
        .navigationTitle(SettingsText.feedbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is on the wall, as on Profile.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .sheet(isPresented: sharing) {
            if case .sharing(let text) = model.phase {
                ShareSheet(text: text, subject: FeedbackComposer.subject) { completed in
                    model.shareFinished(completed: completed)
                }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
            }
        }
        .onDisappear {
            // A sent note has nothing left to keep; the next visit starts a new one.
            if case .sent = model.phase { model.startOver() }
        }
    }

    private var sharing: Binding<Bool> {
        Binding(
            get: {
                if case .sharing = model.phase { return true }
                return false
            },
            set: { isShown in
                if !isShown { model.shareFinished(completed: false) }
            })
    }
}

/// Where VoiceOver goes when Send finds a problem.
enum FeedbackField: Hashable {
    case message
}

/// Send feedback, top to bottom: what it's about, her note, the app details switch, exactly what
/// would be sent, and Send. After sending: thank you, with what went. Separate from
/// `FeedbackScreen` so snapshot tests can draw it.
struct FeedbackPage: View {
    @Bindable var model: FeedbackModel
    let focus: AccessibilityFocusState<FeedbackField?>.Binding
    var send: () -> Void = {}
    var done: () -> Void = {}
    var writeAnother: () -> Void = {}

    var body: some View {
        SettingsPage(
            header: SettingsHeader(
                title: SettingsText.feedbackTitle, lede: SettingsText.feedbackLede, art: .drawersFeedback)
        ) {
            if case .sent(let note) = model.phase {
                sent(note)
            } else {
                writing
            }
        }
    }

    // MARK: Writing

    @ViewBuilder private var writing: some View {
        SettingsGroup(header: FeedbackText.kindHeader, identifier: "feedback.kind") {
            NookFlowLayout {
                ForEach(FeedbackKind.allCases, id: \.self) { kind in
                    NookChip(kind.title, isSelected: model.kind == kind) {
                        model.kind = kind
                    }
                    .accessibilityIdentifier("feedback.kind.\(kind.rawValue)")
                }
            }
            .padding(.horizontal, NookSpacing.small)
            .padding(.bottom, NookSpacing.xSmall)
        }

        VStack(alignment: .leading, spacing: NookSpacing.small) {
            EditorTextField(
                label: FeedbackText.messageLabel(model.kind), prompt: FeedbackText.messagePrompt,
                text: $model.message, isMultiline: true, problem: model.problem.map(FeedbackText.problem),
                identifier: "feedback.message", focus: focus, focusValue: .message)
            Text(FeedbackText.messageHint)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NookSpacing.medium)
        .floorCard()

        SettingsGroup {
            SettingsSwitchRow(
                title: FeedbackText.detailsRow,
                detail: model.includesDetails ? FeedbackText.detailsRowOn : FeedbackText.detailsRowOff,
                systemImage: "info.circle", isOn: model.includesDetails, identifier: "feedback.details",
                set: { model.includesDetails = $0 })
        }

        SettingsGroup(header: FeedbackText.previewHeader, identifier: "feedback.preview") {
            preview(model.preview)
            SettingsNote(FeedbackText.neverSent)
        }

        VStack(alignment: .leading, spacing: NookSpacing.small) {
            NookButton(FeedbackText.send, systemImage: "paperplane", fillsWidth: true, action: send)
                .accessibilityIdentifier("feedback.send")
            Label {
                Text(FeedbackText.howItGoes)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock")
                    .accessibilityHidden(true)
            }
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .padding(.horizontal, NookSpacing.small)
            .padding(.vertical, NookSpacing.xSmall)
            .floorCard()
        }
    }

    /// The exact text, on a stronger tint, or a line saying it'll show here.
    private func preview(_ text: String?) -> some View {
        Text(text ?? FeedbackText.previewEmpty)
            .nookTextStyle(text == nil ? .note : .body)
            .foregroundStyle(text == nil ? Color.nook.textSecondary : Color.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NookSpacing.medium)
            .background(Color.nook.tintStrong, in: NookRadius.shape(NookRadius.button))
            .padding(.horizontal, NookSpacing.xSmall)
            .accessibilityIdentifier("feedback.previewText")
    }

    // MARK: Sent

    @ViewBuilder private func sent(_ note: FeedbackNote) -> some View {
        VStack(spacing: NookSpacing.medium) {
            Image(systemName: "checkmark")
                .font(.title2.weight(.bold))
                .foregroundStyle(.nook.onAccent)
                .frame(width: 56, height: 56)
                .background(Color.nook.accent, in: Circle())
                .accessibilityHidden(true)
            Text(FeedbackText.thanksTitle)
                .nookTextStyle(.title)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(FeedbackText.thanksMessage)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(NookSpacing.large)
        .floorCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feedback.sent")

        SettingsGroup {
            preview(FeedbackComposer.text(note))
        }

        NookAdaptiveStack {
            NookButton(FeedbackText.done, fillsWidth: true, action: done)
                .accessibilityIdentifier("feedback.done")
            NookButton(FeedbackText.writeAnother, kind: .soft, fillsWidth: true, action: writeAnother)
                .accessibilityIdentifier("feedback.writeAnother")
        }
    }
}
