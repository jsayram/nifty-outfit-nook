import DesignSystem
import Models
import SwiftUI

/// A labelled text field for Add a piece: a soft strong tint with a shadow below and no edge,
/// like the search field. Long text wraps at the large text sizes instead of scrolling out of
/// sight, and the prompt is drawn behind the field so it wraps too (playbook, Phase 6).
///
/// A one-line field turns Return into "done". A problem shows under the field on the error
/// tint, in words, with an icon (never colour alone).
struct EditorTextField<Focus: Hashable>: View {
    let label: String
    var isOptional = false
    let prompt: String
    @Binding var text: String
    var isMultiline = false
    var problem: String?
    let identifier: String
    /// Where VoiceOver goes when Save finds a problem here.
    let focus: AccessibilityFocusState<Focus?>.Binding
    let focusValue: Focus

    @Environment(\.closetIsStillImage) private var isStillImage
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            EditorFieldLabel(label: label, isOptional: isOptional)
                .accessibilityHidden(true)
            field
                .padding(.horizontal, 14)
                .padding(.vertical, NookSpacing.small)
                .frame(
                    maxWidth: .infinity, minHeight: max(minHeight, NookSpacing.minimumTapTarget), alignment: .leading
                )
                .background {
                    NookRadius.shape(NookRadius.button)
                        .fill(Color.nook.tintStrong)
                        .softShadow(.drop, in: NookRadius.shape(NookRadius.button))
                }
                .contentShape(NookRadius.shape(NookRadius.button))
                .onTapGesture { isFocused = true }
            if let problem {
                FieldProblemNote(message: problem)
                    .accessibilityIdentifier("problem.\(identifier)")
            }
        }
    }

    @ViewBuilder private var field: some View {
        if isStillImage {
            // ImageRenderer can't draw a text field, so draw what it would show.
            Text(text.isEmpty ? prompt : text)
                .nookTextStyle(.body)
                .foregroundStyle(text.isEmpty ? Color.nook.textSecondary : Color.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(prompt)
                        .nookTextStyle(.body)
                        .foregroundStyle(.nook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
                TextField(text: $text, prompt: Text(verbatim: ""), axis: .vertical) {
                    Text(spokenLabel)
                }
                .lineLimit(isMultiline ? 3...12 : 1...4)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textPrimary)
                .focused($isFocused)
                .submitLabel(isMultiline ? .return : .done)
                .onChange(of: text) { _, newValue in
                    // A vertical field puts Return into the text; one-line fields treat it as done.
                    guard !isMultiline, newValue.contains("\n") else { return }
                    text = newValue.replacing("\n", with: "")
                    isFocused = false
                }
                .accessibilityLabel(Text(spokenLabel))
                .accessibilityIdentifier("field.\(identifier)")
                .accessibilityFocused(focus, equals: focusValue)
            }
        }
    }

    private var spokenLabel: String {
        isOptional ? EditorFieldLabel.spokenOptional(label) : label
    }
}

/// A field's name above it, with "· optional" when it is.
struct EditorFieldLabel: View {
    let label: String
    var isOptional = false

    var body: some View {
        Text(attributed)
            .nookTextStyle(.label)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var text = AttributedString(label)
        guard isOptional else { return text }
        var optional = AttributedString(
            " · "
                + String(localized: "optional", bundle: .module, comment: "Add a piece: after an optional field's name")
        )
        optional.foregroundColor = Color.nook.textSecondary
        text.append(optional)
        return text
    }

    /// "Brand, optional", for VoiceOver.
    static func spokenOptional(_ label: String) -> String {
        String(
            localized: "\(label), optional", bundle: .module,
            comment: "VoiceOver name of an optional field, like Brand, optional")
    }
}

/// A row of chips that choose one value or several, under a heading (Kind, Colour, Fit and so
/// on). The chips always wrap, so none is hidden off screen. VoiceOver hears the heading, then
/// each chip, with "Selected" on the chosen ones.
struct EditorChoiceGroup<Focus: Hashable, Content: View>: View {
    let label: String
    var isOptional = false
    var note: String?
    var problem: String?
    let identifier: String
    let focus: AccessibilityFocusState<Focus?>.Binding
    /// Where VoiceOver goes when Save finds a problem here. `nil` for groups that can't have one.
    var focusValue: Focus?
    @ViewBuilder let content: Content

    @Environment(\.closetIsStillImage) private var isStillImage

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            heading
            NookFlowLayout(spacing: NookSpacing.chipGap, lineSpacing: NookSpacing.xxSmall) { content }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(label))
            if let note {
                Text(note)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem {
                FieldProblemNote(message: problem)
                    .accessibilityIdentifier("problem.\(identifier)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var heading: some View {
        let label = EditorFieldLabel(label: label, isOptional: isOptional)
            .accessibilityAddTraits(.isHeader)
        // ImageRenderer leaves a view with accessibilityFocused blank (playbook, Phase 7a).
        if let focusValue, !isStillImage {
            label.accessibilityFocused(focus, equals: focusValue)
        } else {
            label
        }
    }
}

/// What's wrong with a field, on the error tint, with an icon.
struct FieldProblemNote: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .accessibilityHidden(true)
        }
        .nookTextStyle(.note)
        .foregroundStyle(.nook.error)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.nook.errorSurface, in: NookRadius.shape(NookRadius.small))
        .accessibilityElement(children: .combine)
    }
}
