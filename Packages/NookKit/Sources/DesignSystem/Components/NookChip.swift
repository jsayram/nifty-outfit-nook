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
    private let swatch: Color?
    private let isSelected: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - title: The label, already localized.
    ///   - swatch: A colour dot before the title, for colour filters (LR-09). The title still
    ///     names the colour, so it's never told apart by colour alone.
    public init(
        _ title: String,
        systemImage: String? = nil,
        swatch: Color? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.swatch = swatch
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            NookChipLabel(title: title, systemImage: systemImage, swatch: swatch, isSelected: isSelected)
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
    var swatch: Color?
    let isSelected: Bool
    /// A small symbol after the title, like the chevron on a chip that opens a menu.
    var trailingSystemImage: String?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var pillHeight: CGFloat = 36
    @ScaledMetric(relativeTo: .footnote) private var swatchSize: CGFloat = 14

    var body: some View {
        // The icon is decoration. When the title wouldn't fit on one line beside it, it goes.
        // A swatch stays, since it shows the colour the words name.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                leading
                Text(title).fixedSize()
                trailing
            }
            HStack(spacing: 5) {
                if swatch != nil { leading }
                Text(title)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                trailing
            }
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

    @ViewBuilder private var leading: some View {
        if let swatch {
            // A hairline in the text colour keeps white and cream dots visible on the pill.
            Circle()
                .fill(swatch)
                .overlay(Circle().strokeBorder(Color.nook.textPrimary.opacity(0.25), lineWidth: 1))
                .overlay(Circle().strokeBorder(Color.nook.onAccent.opacity(isSelected ? 0.6 : 0), lineWidth: 1))
                .frame(width: swatchSize, height: swatchSize)
                .accessibilityHidden(true)
        } else if let systemImage {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var trailing: some View {
        if let trailingSystemImage {
            Image(systemName: trailingSystemImage)
                .imageScale(.small)
                .accessibilityHidden(true)
        }
    }
}

/// A chip that opens a menu of choices, such as the Suitcase filter (LR-11): "Suitcase" with a
/// chevron while nothing is chosen, the choice's name as a selected pill once something is.
///
/// ```swift
/// NookMenuChip(filter.suitcaseName ?? "Suitcase", systemImage: "suitcase", isSelected: filter.suitcase != nil) {
///     Picker("Suitcase", selection: $filter.suitcase) { ... }
/// }
/// ```
public struct NookMenuChip<Content: View>: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let content: Content

    @Environment(\.nookStaticRendering) private var isStatic

    /// - Parameter title: The label, already localized: what the menu chooses, or the choice.
    public init(_ title: String, systemImage: String? = nil, isSelected: Bool, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.content = content()
    }

    public var body: some View {
        if isStatic {
            // ImageRenderer can't draw a menu button, so draw its label.
            label
        } else {
            Menu {
                content
            } label: {
                label
            }
            .buttonStyle(NookChipButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private var label: some View {
        NookChipLabel(
            title: title, systemImage: systemImage, isSelected: isSelected, trailingSystemImage: "chevron.down")
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
