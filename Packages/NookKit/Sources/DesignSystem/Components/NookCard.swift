import SwiftUI

/// The fill of a soft card.
nonisolated public enum NookCardFill: Sendable {
    /// The usual see-through wash over the wall.
    case tint
    /// A stronger wash, for cards that sit on drawn art.
    case strong
    /// The butter note colour, for a gentle heads-up.
    case warning

    var color: Color {
        switch self {
        case .tint: .nook.tint
        case .strong: .nook.tintStrong
        case .warning: .nook.warningSurface
        }
    }
}

extension View {
    /// Puts the view on a soft card: a tint with rounded corners and a shadow that falls only
    /// below. No outline. Use it sparingly; most groups need only space, a `NookSection` header
    /// and a `NookDivider`.
    public func nookCard(_ fill: NookCardFill = .tint, padding: CGFloat = NookSpacing.groupPadding) -> some View {
        self
            .padding(padding)
            .background {
                NookRadius.shape(NookRadius.group)
                    .fill(fill.color)
                    .softShadow(.drop, in: NookRadius.shape(NookRadius.group))
            }
    }
}

/// A group of rows with an optional header and a note underneath (`.sec-h`, `.grp`, `.note`).
/// No box: the header and the space around the group do the separating.
public struct NookSection<Content: View>: View {
    private let header: String?
    private let detail: String?
    private let footer: String?
    private let content: Content

    /// - Parameters:
    ///   - header: A short heading above the rows, already localized. So are `detail` and `footer`.
    ///   - detail: Quiet text at the header's trailing end, like "3 of 5".
    ///   - footer: A short note under the rows.
    public init(
        _ header: String? = nil,
        detail: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header
        self.detail = detail
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            if let header {
                NookSectionHeader(header, detail: detail)
            }
            VStack(spacing: NookSpacing.xxSmall) { content }
            if let footer {
                Text(footer)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NookSpacing.medium)
                    .padding(.top, NookSpacing.xxSmall)
            }
        }
    }
}

/// A section heading: quiet, bold and small, read by VoiceOver as a heading.
/// An optional detail sits at the trailing end, and moves under the heading at large text sizes.
public struct NookSectionHeader: View {
    private let title: String
    private let detail: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameter title: The heading, already localized. So is `detail`.
    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.xxSmall))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: NookSpacing.small))
        layout {
            Text(title)
                .nookTextStyle(.chip)
                .fontWeight(.bold)
                .foregroundStyle(.nook.textSecondary)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let detail {
                Text(detail)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, NookSpacing.medium)
        .padding(.top, NookSpacing.small)
    }
}

/// A 1 point line that fades out at both ends and never reaches the edges (`.soft-div`).
/// Put it between groups, never between rows. VoiceOver skips it.
public struct NookDivider: View {
    private let inset: CGFloat

    /// - Parameter inset: How far in from each side the line starts. The mockups use 36.
    public init(inset: CGFloat = 36) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(Color.nook.softDivider)
            .frame(height: 1)
            .padding(.horizontal, inset)
            .padding(.vertical, NookSpacing.medium)
            .accessibilityHidden(true)
    }
}
