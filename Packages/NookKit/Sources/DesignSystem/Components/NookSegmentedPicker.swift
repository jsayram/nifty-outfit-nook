import SwiftUI

/// A switch between two or three views of the same thing, like Looks | Pictures or
/// Simple · Dressed up · Something new (`.seg`, `.vers` in the mockups).
///
/// A soft tinted track with the chosen option as a solid accent pill. Each option is at least
/// 44 points tall. When the labels don't fit side by side (large text), the options stack
/// instead of truncating. The pill slides between options, or simply moves when Reduce
/// Motion is on. VoiceOver reads each option as a button, the chosen one as "Selected".
public struct NookSegmentedPicker<Value: Hashable>: View {
    /// One option: its value, its label (already localized) and an optional SF Symbol.
    public struct Option: Identifiable {
        public let value: Value
        public let title: String
        public let systemImage: String?
        /// What VoiceOver says after the option's name, already localized, such as what the
        /// option shows ("Easy and safe").
        public let hint: String?
        /// An accessibility identifier for UI tests.
        public let identifier: String?

        public init(
            _ value: Value, title: String, systemImage: String? = nil, hint: String? = nil, identifier: String? = nil
        ) {
            self.value = value
            self.title = title
            self.systemImage = systemImage
            self.hint = hint
            self.identifier = identifier
        }

        public var id: Value { value }
    }

    private let title: String
    private let options: [Option]
    @Binding private var selection: Value

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    /// - Parameter title: What the options choose between, already localized. VoiceOver reads it;
    ///   it isn't shown.
    public init(_ title: String, selection: Binding<Value>, options: [Option]) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            track(HStack(spacing: NookSpacing.xSmall) { segments(sideBySide: true) })
            track(VStack(spacing: NookSpacing.xSmall) { segments(sideBySide: false) })
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private func track(_ content: some View) -> some View {
        content
            .padding(NookSpacing.xSmall)
            .background {
                NookRadius.shape(NookRadius.group)
                    .fill(Color.nook.tint)
                    .softShadow(.drop, in: NookRadius.shape(NookRadius.group))
            }
    }

    private func segments(sideBySide: Bool) -> some View {
        ForEach(options) { option in
            let isSelected = option.value == selection
            Button {
                if reduceMotion {
                    selection = option.value
                } else {
                    withAnimation(.snappy(duration: 0.25)) { selection = option.value }
                }
            } label: {
                HStack(spacing: 6) {
                    if let systemImage = option.systemImage {
                        Image(systemName: systemImage)
                            .accessibilityHidden(true)
                    }
                    Text(option.title)
                        .multilineTextAlignment(.center)
                        // Side by side, a label keeps to one line so ViewThatFits can tell when
                        // the options need to stack instead.
                        .fixedSize(horizontal: sideBySide, vertical: true)
                }
                .nookTextStyle(.label)
                .foregroundStyle(isSelected ? Color.nook.onAccent : Color.nook.accent)
                .padding(.horizontal, NookSpacing.medium)
                .padding(.vertical, NookSpacing.small)
                .frame(maxWidth: .infinity, minHeight: NookSpacing.minimumTapTarget)
                .background {
                    if isSelected {
                        NookRadius.shape(NookRadius.button)
                            .fill(Color.nook.accent)
                            .softShadow(.drop, in: NookRadius.shape(NookRadius.button))
                            .matchedGeometryEffect(id: "selection", in: pill)
                    }
                }
                .contentShape(NookRadius.shape(NookRadius.button))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(Text(option.hint ?? ""))
            .accessibilityIdentifier(option.identifier ?? "")
        }
    }
}
