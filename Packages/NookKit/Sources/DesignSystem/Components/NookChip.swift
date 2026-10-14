import SwiftUI

/// A selectable pill, for filters and quick choices (`.chip` in the mockups).
///
/// Unselected chips are a soft tint with a shadow below. The selected chip is a solid accent
/// pill. There's never an outline. The visible pill is 36 points tall at the default text size,
/// and the tap target around it is at least 44. VoiceOver reads it as a button, and as
/// "Selected" when it's on.
public struct NookChip: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let action: () -> Void

    /// - Parameter title: The label, already localized.
    public init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            NookChipLabel(title: title, systemImage: systemImage, isSelected: isSelected)
        }
        .buttonStyle(NookChipButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NookChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct NookChipLabel: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var pillHeight: CGFloat = 36

    var body: some View {
        // The icon is decoration. When the title wouldn't fit on one line beside it, it goes.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title).fixedSize()
            }
            Text(title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .nookTextStyle(.chip)
        .foregroundStyle(isSelected ? Color.nook.onAccent : Color.nook.textPrimary)
        .padding(.horizontal, 13)
        .padding(.vertical, NookSpacing.small)
        .frame(minHeight: pillHeight)
        .background {
            Capsule()
                .fill(isSelected ? Color.nook.accent : Color.nook.tint)
                .softShadow(.drop, in: Capsule(), isVisible: isEnabled)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isSelected)
        // The 44 point tap target reaches past the visible pill.
        .frame(minHeight: NookSpacing.minimumTapTarget)
        .contentShape(Rectangle())
    }
}

/// How a row of chips lays itself out.
nonisolated public enum NookChipBarLayout: Sendable {
    /// One line that scrolls sideways at standard text sizes, wrapping onto more lines at the
    /// accessibility sizes so no chip is hidden off screen.
    case automatic
    /// Always one line that scrolls sideways.
    case scroll
    /// Always wraps onto as many lines as it needs.
    case wrap
}

/// A row of chips: a filter bar (L9, L11) or a set of quick choices.
///
/// ```swift
/// NookChipBar("Piece type") {
///     ForEach(PieceType.allCases) { type in
///         NookChip(type.title, isSelected: filter.contains(type)) { filter.toggle(type) }
///     }
/// }
/// ```
///
/// The bar is one VoiceOver container named by `title`, so people hear which group of chips
/// they're in.
public struct NookChipBar<Content: View>: View {
    private let title: String
    private let layout: NookChipBarLayout
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.nookStaticRendering) private var isStatic

    /// - Parameters:
    ///   - title: What the chips choose between, already localized. VoiceOver reads it; it isn't shown.
    ///   - layout: Scroll or wrap. `.automatic` wraps only at the accessibility text sizes.
    public init(_ title: String, layout: NookChipBarLayout = .automatic, @ViewBuilder content: () -> Content) {
        self.title = title
        self.layout = layout
        self.content = content()
    }

    public var body: some View {
        Group {
            if wraps {
                NookFlowLayout(spacing: NookSpacing.chipGap, lineSpacing: NookSpacing.xSmall) { content }
                    .padding(.horizontal, NookSpacing.screenMargin)
            } else if isStatic {
                // ImageRenderer can't draw a scroll view, so show the first screenful.
                LeadingOverflowLayout {
                    HStack(spacing: NookSpacing.chipGap) { content }
                        .padding(.horizontal, NookSpacing.screenMargin)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: NookSpacing.chipGap) { content }
                        .padding(.horizontal, NookSpacing.screenMargin)
                }
                .scrollIndicators(.hidden)
                // Let the soft shadows below the chips show instead of being cut off.
                .scrollClipDisabled()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private var wraps: Bool {
        switch layout {
        case .automatic: dynamicTypeSize.isAccessibilitySize
        case .scroll: false
        case .wrap: true
        }
    }
}
