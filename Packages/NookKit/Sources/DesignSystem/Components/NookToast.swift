import SwiftUI

/// A short message that confirms something happened, with an optional action like Undo
/// (the toasts in Closet, Laundry, Profile and Swap).
public struct NookToastMessage: Identifiable, Equatable {
    public let id: UUID
    public let message: String
    public let systemImage: String?
    public let actionTitle: String?
    public let action: (() -> Void)?

    /// - Parameters:
    ///   - message: What happened, already localized, like "Removed the cardigan". So is `actionTitle`.
    ///   - actionTitle: A short action, like "Undo". Shown only with an `action`.
    public init(
        _ message: String,
        systemImage: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.id = UUID()
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension View {
    /// Shows `toast` at the bottom of the view, then clears it after a few seconds.
    ///
    /// It stays longer while VoiceOver is running, and VoiceOver announces it when it appears.
    /// It slides up, or fades in when Reduce Motion is on.
    public func nookToast(_ toast: Binding<NookToastMessage?>) -> some View {
        modifier(NookToastPresenter(toast: toast))
    }
}

private struct NookToastPresenter: ViewModifier {
    @Binding var toast: NookToastMessage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack {
                    if let toast {
                        NookToast(toast) { self.toast = nil }
                            .padding(.horizontal, NookSpacing.xLarge)
                            .padding(.bottom, NookSpacing.large)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy, value: toast?.id)
            }
            .task(id: toast?.id) {
                guard let toast else { return }
                AccessibilityNotification.Announcement(toast.message).post()
                // A toast with an action stays longer, and longer still with VoiceOver.
                let seconds = (toast.action == nil ? 4.0 : 6.0) * (voiceOverEnabled ? 2.5 : 1)
                try? await Task.sleep(for: .seconds(seconds))
                if self.toast?.id == toast.id {
                    self.toast = nil
                }
            }
    }
}

/// The toast itself: a dark pill (light in dark mode) with a soft shadow, at most 480 points wide.
public struct NookToast: View {
    private let toast: NookToastMessage
    private let onAction: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameter onAction: Runs after the toast's own action, so the presenter can close it.
    public init(_ toast: NookToastMessage, onAction: @escaping () -> Void = {}) {
        self.toast = toast
        self.onAction = onAction
    }

    public var body: some View {
        // At the accessibility sizes the action goes under the message, so neither is squeezed
        // until words break mid-word.
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let systemImage = toast.systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(toast.message)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            if let actionTitle = toast.actionTitle, let action = toast.action {
                Button {
                    action()
                    onAction()
                } label: {
                    Text(actionTitle)
                        .nookTextStyle(.label)
                        .underline()
                        .padding(.horizontal, NookSpacing.small)
                        .frame(minWidth: NookSpacing.minimumTapTarget, minHeight: NookSpacing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Under the message, the word lines up with it rather than with its padding.
                .padding(.leading, dynamicTypeSize.isAccessibilitySize ? -NookSpacing.small : 0)
            }
        }
        .nookTextStyle(.note)
        .fontWeight(.medium)
        .foregroundStyle(.nook.background)
        .padding(.leading, NookSpacing.large)
        .padding(.trailing, toast.action == nil ? NookSpacing.large : NookSpacing.xSmall)
        .padding(.vertical, toast.action == nil ? NookSpacing.medium : NookSpacing.xxSmall)
        .frame(maxWidth: 480, minHeight: 48)
        .background {
            NookRadius.shape(NookRadius.group)
                .fill(Color.nook.textPrimary)
                .softShadow(.dropLarge, in: NookRadius.shape(NookRadius.group))
        }
    }
}
