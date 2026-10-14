import SwiftUI

extension View {
    /// Presents a system bottom sheet with the app's styled header: a serif title, an optional
    /// line under it, and a Close button. The sheet has a grabber, the large sheet corners and
    /// the wall colour behind it, and its content scrolls when it doesn't fit.
    ///
    /// At the accessibility text sizes the sheet always opens full height, so nothing is hidden
    /// below a half-height sheet.
    ///
    /// - Parameters:
    ///   - title: The sheet's heading, already localized. So is `subtitle`.
    ///   - detents: The heights it can rest at. Defaults to half and full height.
    public func nookSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            NookSheetContainer(title: title, subtitle: subtitle, content: content)
                .modifier(NookSheetPresentation(detents: detents))
        }
    }

    /// Presents a styled bottom sheet for an item, like `sheet(item:)`. See
    /// `nookSheet(isPresented:title:subtitle:detents:onDismiss:content:)`.
    public func nookSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        title: @escaping (Item) -> String,
        subtitle: ((Item) -> String?)? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            NookSheetContainer(title: title(item), subtitle: subtitle?(item)) { content(item) }
                .modifier(NookSheetPresentation(detents: detents))
        }
    }
}

private struct NookSheetPresentation: ViewModifier {
    let detents: Set<PresentationDetent>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(NookRadius.sheet)
            .presentationBackground { Color.nook.wallGradient }
    }
}

/// The inside of a styled sheet: header, then the content, scrolling as one. `nookSheet` wraps
/// your content in it; you don't usually need it directly.
public struct NookSheetContainer<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content

    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title2) private var closeSize: CGFloat = 32

    public init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        StaticAwareScrollView {
            VStack(alignment: .leading, spacing: NookSpacing.large) {
                header
                content
            }
            .padding(.horizontal, NookSpacing.xLarge)
            .padding(.top, NookSpacing.xxLarge)
            .padding(.bottom, NookSpacing.xxxLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            HStack(alignment: .top, spacing: NookSpacing.medium) {
                Text(title)
                    .nookTextStyle(.title)
                    .foregroundStyle(.nook.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                closeButton
            }
            // Under the title row, so it gets the full width.
            if let subtitle {
                Text(subtitle)
                    .nookTextStyle(.body)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: closeSize * 0.44, weight: .bold, design: .rounded))
                .foregroundStyle(.nook.accent)
                .frame(width: closeSize, height: closeSize)
                .background(Color.nook.tint, in: Circle())
                .frame(minWidth: NookSpacing.minimumTapTarget, minHeight: NookSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close", bundle: .module, comment: "Button that closes a sheet"))
    }
}
