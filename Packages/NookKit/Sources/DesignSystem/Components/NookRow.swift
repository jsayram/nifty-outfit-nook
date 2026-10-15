import SwiftUI

/// A list row with no box and no separator lines (`.item` in Profile, `.erow` in Your looks).
///
/// A round tinted icon, a title, an optional subtitle, an optional value and an optional
/// chevron. Rows are told apart by space and their icons. At the accessibility text sizes the
/// value moves under the title so nothing is cut off.
///
/// `NookRow` is the content only. To make it tappable, put it in a `Button` or
/// `NavigationLink` with the row style:
///
/// ```swift
/// NavigationLink { FitScreen() } label: {
///     NookRow("Fit and measurements", subtitle: "Used for size suggestions", systemImage: "ruler", accessory: .chevron)
/// }
/// .buttonStyle(.nookRow)
/// ```
public struct NookRow: View {
    /// What sits at the trailing end.
    nonisolated public enum Accessory: Sendable {
        case none
        /// A disclosure chevron: the row opens something.
        case chevron
    }

    private let title: String
    private let subtitle: String?
    private let value: String?
    private let systemImage: String?
    private let iconFill: Color
    private let accessory: Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 32
    @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 52

    /// - Parameters:
    ///   - title: The row's label, already localized. So are `subtitle` and `value`.
    ///   - value: The current setting, shown at the end, like "1 week".
    ///   - systemImage: An SF Symbol in a round tint before the title.
    ///   - iconFill: The tint behind the icon. Defaults to the strong white tint.
    public init(
        _ title: String,
        subtitle: String? = nil,
        value: String? = nil,
        systemImage: String? = nil,
        iconFill: Color = .nook.tintStrong,
        accessory: Accessory = .none
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.systemImage = systemImage
        self.iconFill = iconFill
        self.accessory = accessory
    }

    public var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        HStack(alignment: stacked ? .top : .center, spacing: NookSpacing.medium) {
            if !stacked {
                icon
            }
            VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                // At the accessibility sizes the icon sits above the title, with the chevron on
                // its line, so the words get the whole width instead of breaking mid-word.
                if stacked {
                    HStack(alignment: .center) {
                        icon
                        if chevronBesideIcon {
                            Spacer(minLength: NookSpacing.small)
                            chevron
                        }
                    }
                    .padding(.bottom, NookSpacing.xSmall)
                }
                Text(title)
                    .nookTextStyle(.label)
                    .foregroundStyle(.nook.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                }
                if stacked, let value {
                    valueText(value)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stacked, let value {
                valueText(value)
            }
            if accessory == .chevron, !(stacked && chevronBesideIcon) {
                chevron
            }
        }
        .padding(.horizontal, NookSpacing.medium)
        .padding(.vertical, 6)
        .frame(minHeight: max(minHeight, NookSpacing.minimumTapTarget))
        .contentShape(NookRadius.shape(NookRadius.group))
        .accessibilityElement(children: .combine)
    }

    /// At the accessibility sizes a row with an icon puts its chevron beside the icon, above the
    /// words, instead of in a column of its own (Phase 14a: "Fit and measurements" broke as
    /// "measure-ments" at AX5).
    private var chevronBesideIcon: Bool {
        accessory == .chevron && systemImage != nil
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.nook.chevron)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var icon: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: iconSize * 0.56, weight: .semibold, design: .rounded))
                .foregroundStyle(.nook.accent)
                .frame(width: iconSize, height: iconSize)
                .background(iconFill, in: Circle())
                .accessibilityHidden(true)
        }
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .nookTextStyle(.label)
            .fontWeight(.medium)
            .foregroundStyle(.nook.textSecondary)
    }
}

/// The style for a tappable `NookRow`: a soft tint shows while it's pressed, never a box.
public struct NookRowButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    NookRadius.shape(NookRadius.group).fill(Color.nook.tint)
                }
            }
    }
}

extension ButtonStyle where Self == NookRowButtonStyle {
    /// The style for tappable rows, for example `.buttonStyle(.nookRow)`.
    public static var nookRow: NookRowButtonStyle { NookRowButtonStyle() }
}
