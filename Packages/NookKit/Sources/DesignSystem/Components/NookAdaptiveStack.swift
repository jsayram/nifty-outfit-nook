import SwiftUI

/// Side by side at standard text sizes, one above the other at the accessibility sizes.
/// For pairs of buttons and other actions that would squeeze their words at large text
/// (the results actions become one column at the largest size in the mockups).
public struct NookAdaptiveStack<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(spacing: CGFloat = NookSpacing.small, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: spacing))
        layout { content }
    }
}
