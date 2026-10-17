import SwiftUI

/// An inline search field on a soft tint with a shadow below and no edge (`.search` in
/// Saved Looks and Closet).
///
/// A clear button appears once there's text. It's a full 44 point target and VoiceOver reads it
/// as "Clear search". Search happens on the device; this view only holds the text.
public struct NookSearchField: View {
    @Binding private var text: String
    private let prompt: String
    private let onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.nookStaticRendering) private var isStatic
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 48

    /// - Parameters:
    ///   - prompt: The placeholder, already localized, like "Search your looks". VoiceOver uses
    ///     it as the field's name.
    ///   - onSubmit: Called when she presses Search on the keyboard.
    public init(_ prompt: String, text: Binding<String>, onSubmit: @escaping () -> Void = {}) {
        self.prompt = prompt
        self._text = text
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: NookSpacing.small) {
            Image(systemName: "magnifyingglass")
                .font(Font.nook.body.weight(.medium))
                // The glyph stops growing at AX2, so a long word in the prompt ("pictures" at
                // AX5 on a 402 point iPhone) has room and doesn't push the field past the
                // screen's edge (QA, October 2026).
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .foregroundStyle(.nook.textSecondary)
                .accessibilityHidden(true)
            field
                .frame(maxWidth: .infinity, alignment: .leading)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Font.nook.body)
                        .foregroundStyle(.nook.textSecondary)
                        .frame(minWidth: NookSpacing.minimumTapTarget, minHeight: NookSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text("Clear search", bundle: .module, comment: "Button that empties a search field"))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, text.isEmpty ? 14 : NookSpacing.xxSmall)
        .frame(minHeight: max(minHeight, NookSpacing.minimumTapTarget))
        .background {
            NookRadius.shape(NookRadius.button)
                .fill(Color.nook.tintStrong)
                .softShadow(.drop, in: NookRadius.shape(NookRadius.button))
        }
    }

    @ViewBuilder private var field: some View {
        if isStatic {
            // ImageRenderer can't draw a text field, so draw what it would show.
            Text(text.isEmpty ? prompt : text)
                .nookTextStyle(.body)
                .foregroundStyle(text.isEmpty ? Color.nook.textSecondary : Color.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Vertical, so a long query wraps at large text sizes instead of scrolling out of
            // sight. Return still means "search", never a new line. The system draws a field's
            // prompt on one line and truncates it ("Search yo..." at AX5), so the prompt is a
            // wrapping text behind the field instead; the field's label still names it.
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
                textField
            }
        }
    }

    private var textField: some View {
        TextField(text: $text, prompt: Text(verbatim: ""), axis: .vertical) {
            Text(prompt)
        }
        .lineLimit(1...4)
        .nookTextStyle(.body)
        .foregroundStyle(.nook.textPrimary)
        .focused($isFocused)
        .submitLabel(.search)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onSubmit(onSubmit)
        .onChange(of: text) { _, newValue in
            guard newValue.contains("\n") else { return }
            text = newValue.replacing("\n", with: "")
            isFocused = false
            onSubmit()
        }
        // The visible prompt is a separate text, so name the field here.
        .accessibilityLabel(Text(prompt))
        .accessibilityAddTraits(.isSearchField)
    }
}
