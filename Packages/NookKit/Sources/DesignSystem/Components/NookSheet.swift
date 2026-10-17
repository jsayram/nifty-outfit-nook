import SwiftUI

extension View {
    /// Presents a system bottom sheet with the app's styled header: a serif title, an optional
    /// line under it, and a Close button. The sheet has a grabber, the large sheet corners and
    /// the wall colour behind it, and its content scrolls when it doesn't fit.
    ///
    /// At the accessibility text sizes the sheet always opens full height, so nothing is hidden
    /// below a half-height sheet.
    ///
    /// In a regular-width window (iPad, Phase 15b) the sheet is a form in the middle of the
    /// screen instead. One that may rest at half height is only as tall as its content, so a
    /// short sheet isn't a tall empty card; one that only opens full height (a list with search)
    /// keeps the form's full height, so it doesn't jump as the list changes. The detents would
    /// stop the form fitting its content, so they're only set in a compact window.
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
        modifier(
            NookSheetModifier(
                isPresented: isPresented, title: title, subtitle: subtitle, detents: detents, onDismiss: onDismiss,
                sheetContent: content))
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
        modifier(
            NookItemSheetModifier(
                item: item, title: title, subtitle: subtitle, detents: detents, onDismiss: onDismiss,
                sheetContent: content))
    }
}

/// Something the app draws over every styled sheet, above the header and content: Features puts
/// a quick tour there when the tour's step is on a sheet (Stage A audit), since anything drawn
/// under the sheet is covered by it. Set it once near the root; sheets inherit it.
public struct NookSheetOverlay: Sendable {
    let make: @MainActor @Sendable () -> AnyView

    public init(_ make: @escaping @MainActor @Sendable () -> AnyView) {
        self.make = make
    }
}

extension EnvironmentValues {
    /// Drawn over every `nookSheet`. `nil`, the default, draws nothing.
    @Entry public var nookSheetOverlay: NookSheetOverlay? = nil
}

/// `nookSheet(isPresented:…)`. A modifier, so it can read the width class of the window the
/// sheet opens over, which picks a bottom sheet or a form.
private struct NookSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let subtitle: String?
    let detents: Set<PresentationDetent>
    let onDismiss: (() -> Void)?
    let sheetContent: () -> SheetContent

    @Environment(\.horizontalSizeClass) private var windowSizeClass
    @Environment(\.nookSheetOverlay) private var overlay

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
            NookSheetContainer(title: title, subtitle: subtitle, content: sheetContent)
                .overlay { overlay?.make() }
                .modifier(NookSheetPresentation(detents: detents, isForm: windowSizeClass == .regular))
        }
    }
}

/// `nookSheet(item:…)`, as `NookSheetModifier`.
private struct NookItemSheetModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    let title: (Item) -> String
    let subtitle: ((Item) -> String?)?
    let detents: Set<PresentationDetent>
    let onDismiss: (() -> Void)?
    let sheetContent: (Item) -> SheetContent

    @Environment(\.horizontalSizeClass) private var windowSizeClass
    @Environment(\.nookSheetOverlay) private var overlay

    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: onDismiss) { item in
            NookSheetContainer(title: title(item), subtitle: subtitle?(item)) { sheetContent(item) }
                .overlay { overlay?.make() }
                .modifier(NookSheetPresentation(detents: detents, isForm: windowSizeClass == .regular))
        }
    }
}

private struct NookSheetPresentation: ViewModifier {
    let detents: Set<PresentationDetent>
    /// Over a regular-width window, where the system shows a form rather than a bottom sheet.
    let isForm: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        Group {
            if isForm {
                // Detents would stop the form fitting its content.
                content
                    .presentationSizing(.form.fitted(horizontal: false, vertical: detents != [.large]))
            } else {
                content
                    .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : detents)
            }
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var closeSize: CGFloat = 32
    @Environment(\.nookStaticRendering) private var isStatic
    /// The header and content's height, which a form sheet on iPad sizes itself to.
    @State private var contentHeight: CGFloat = 0

    public init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        if isStatic {
            // A still image draws the whole content without a scroll view.
            column
        } else {
            ScrollView {
                column
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })
            }
            .scrollIndicators(.hidden)
            // A scroll view has no height of its own to offer, so a fitted form sheet (iPad,
            // Phase 15b) is told its content's.
            .frame(idealHeight: contentHeight > 0 ? contentHeight : nil)
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            header
            content
        }
        .padding(.horizontal, NookSpacing.xLarge)
        .padding(.top, NookSpacing.xxLarge)
        .padding(.bottom, NookSpacing.xxxLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            if dynamicTypeSize.isAccessibilitySize {
                // At the largest sizes Close sits on its own line above the title, so a one-word
                // title like "Preferences" gets the full width instead of breaking mid-word.
                closeButton.frame(maxWidth: .infinity, alignment: .trailing)
                titleText
            } else {
                HStack(alignment: .top, spacing: NookSpacing.medium) {
                    titleText
                    closeButton
                }
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

    private var titleText: some View {
        Text(title)
            .nookTextStyle(.title)
            .foregroundStyle(.nook.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        // Escape (and Command-period) on a hardware keyboard closes the sheet.
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(Text("Close", bundle: .module, comment: "Button that closes a sheet"))
    }
}
