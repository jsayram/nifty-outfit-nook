import SwiftUI

/// The look of a button. Every kind keeps a tap target of at least 44 points.
nonisolated public enum NookButtonKind: String, CaseIterable, Sendable {
    /// The main action on a screen: a solid accent fill with gently rounded corners (`.btn`).
    case primary
    /// A quieter action beside a primary one: a soft tint, accent text, no edge (`.btn.ghost`).
    case soft
    /// A small soft capsule for actions that sit inside content, like "Show 3 more" (`.shuffle`).
    case pill
    /// A text-only action, like "See all" or "Clear" (`.link`, `.lnk`).
    case text
}

/// How big a button is. Text still grows with Dynamic Type at both sizes.
nonisolated public enum NookButtonSize: String, CaseIterable, Sendable {
    /// 50 points tall at the default text size (`.btn`).
    case regular
    /// 44 points tall, with the smaller label (`.btn.small`, `.grid4 .btn`).
    case small
}

/// A button style for the soft, no-box look. Use it on any `Button`:
///
/// ```swift
/// Button("Save look", systemImage: "bookmark") { save() }
///     .buttonStyle(.nook(.primary))
/// ```
///
/// Pressed buttons darken (and shrink very slightly unless Reduce Motion is on). Disabled
/// buttons fade and lose their shadow. For a loading state, use `NookButton`.
public struct NookButtonStyle: ButtonStyle {
    public var kind: NookButtonKind
    public var size: NookButtonSize

    public init(_ kind: NookButtonKind = .primary, size: NookButtonSize = .regular) {
        self.kind = kind
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        NookButtonChrome(kind: kind, size: size, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

extension ButtonStyle where Self == NookButtonStyle {
    /// The app's button style, for example `.buttonStyle(.nook(.soft))`.
    public static func nook(_ kind: NookButtonKind = .primary, size: NookButtonSize = .regular) -> NookButtonStyle {
        NookButtonStyle(kind, size: size)
    }
}

/// A button with a title, an optional SF Symbol and an optional loading state.
///
/// While `isLoading` is true the symbol becomes a loading indicator, the title stays, and the
/// button ignores taps but keeps its colour. VoiceOver reads the title, then "Loading".
public struct NookButton: View {
    private let title: String
    private let systemImage: String?
    private let kind: NookButtonKind
    private let size: NookButtonSize
    private let isLoading: Bool
    private let fillsWidth: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - title: The label, already localized.
    ///   - systemImage: An SF Symbol shown before the title.
    ///   - fillsWidth: Stretch to the width offered, as the stacked actions in the mockups do.
    public init(
        _ title: String,
        systemImage: String? = nil,
        kind: NookButtonKind = .primary,
        size: NookButtonSize = .regular,
        isLoading: Bool = false,
        fillsWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.size = size
        self.isLoading = isLoading
        self.fillsWidth = fillsWidth
        self.action = action
    }

    public var body: some View {
        Button {
            // Not `.disabled`: a loading button keeps its colour, it just ignores taps.
            if !isLoading { action() }
        } label: {
            NookButtonLabel(title: title, systemImage: systemImage, isLoading: isLoading, fillsWidth: fillsWidth)
        }
        .buttonStyle(.nook(kind, size: size))
        .allowsHitTesting(!isLoading)
        .accessibilityValue(
            isLoading ? Text("Loading", bundle: .module, comment: "Spoken while something loads") : Text(""))
    }
}

/// The inside of a `NookButton`: an icon or loading indicator, then the title, wrapping onto
/// more lines at large text sizes instead of truncating.
struct NookButtonLabel: View {
    let title: String
    let systemImage: String?
    var isLoading = false
    var fillsWidth = false

    var body: some View {
        // Icon beside the title while the title fits on one line; at large text sizes the icon
        // goes above it, so the title gets the full width and wraps between words.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NookSpacing.small) {
                icon
                Text(title).fixedSize()
            }
            VStack(spacing: NookSpacing.xSmall) {
                icon
                Text(title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
    }

    @ViewBuilder private var icon: some View {
        if isLoading {
            // The button's accessibility value already says "Loading".
            NookLoadingIndicator(size: .small)
                .accessibilityHidden(true)
        } else if let systemImage {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
    }
}

/// Draws a button of any kind in any state. `NookButtonStyle` uses it with the real pressed
/// state; the catalog uses it directly to show a pressed button.
struct NookButtonChrome<Label: View>: View {
    let kind: NookButtonKind
    let size: NookButtonSize
    let isPressed: Bool
    @ViewBuilder let label: Label

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .callout) private var regularHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .subheadline) private var smallHeight: CGFloat = 44

    var body: some View {
        label
            .nookTextStyle(textStyle)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, kind == .text ? NookSpacing.xSmall : NookSpacing.small)
            .frame(minHeight: minHeight)
            .background { fill }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(isPressed && !reduceMotion && kind != .text ? 0.97 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isPressed)
    }

    private var textStyle: NookTextStyle {
        switch (kind, size) {
        case (.primary, .regular), (.soft, .regular), (.text, .regular): .button
        default: .label
        }
    }

    private var minHeight: CGFloat {
        switch (kind, size) {
        case (.pill, _), (.text, _), (_, .small): max(smallHeight, NookSpacing.minimumTapTarget)
        default: max(regularHeight, NookSpacing.minimumTapTarget)
        }
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .primary, .soft: size == .regular ? 18 : NookSpacing.medium
        case .pill: NookSpacing.large
        case .text: NookSpacing.small
        }
    }

    private var shape: AnyShape {
        switch kind {
        case .pill: AnyShape(Capsule())
        default: AnyShape(NookRadius.shape(size == .regular ? NookRadius.button : NookRadius.buttonSmall))
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .nook.onAccent
        case .soft, .pill, .text: isPressed ? .nook.accentPressed : .nook.accent
        }
    }

    @ViewBuilder private var fill: some View {
        switch kind {
        case .primary:
            shape.fill(isPressed ? Color.nook.accentPressed : Color.nook.accent)
                .softShadow(.dropLarge, in: shape, isVisible: isEnabled && !isPressed)
        case .soft:
            shape.fill(isPressed ? Color.nook.track : Color.nook.tint)
                .softShadow(.drop, in: shape, isVisible: isEnabled && !isPressed)
        case .pill:
            shape.fill(isPressed ? Color.nook.track : Color.nook.tintStrong)
                .softShadow(.drop, in: shape, isVisible: isEnabled && !isPressed)
        case .text:
            shape.fill(isPressed ? Color.nook.tint : Color.clear)
        }
    }
}
