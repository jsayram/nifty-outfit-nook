import SwiftUI

extension EnvironmentValues {
    /// True when a view is drawn to a still image with `ImageRenderer`, as the snapshot tests do.
    ///
    /// `ImageRenderer` can't draw views that UIKit backs, such as text fields and scroll views,
    /// and puts a placeholder in their place. Components that use one swap it for plain SwiftUI
    /// that looks the same while this is on. It's never on in the app.
    @Entry var nookStaticRendering = false
}

/// A scroll view that becomes a plain stack when the view is drawn to a still image.
struct StaticAwareScrollView<Content: View>: View {
    let axis: Axis.Set
    @ViewBuilder let content: Content

    @Environment(\.nookStaticRendering) private var isStatic

    init(_ axis: Axis.Set = .vertical, @ViewBuilder content: () -> Content) {
        self.axis = axis
        self.content = content()
    }

    var body: some View {
        if isStatic {
            content
        } else {
            ScrollView(axis) { content }
                .scrollIndicators(.hidden)
        }
    }
}

/// Takes the width it's offered, whatever its content's width, and lines the content up at the
/// leading edge. A stand-in for a sideways scroll view in still images: the row runs off the
/// trailing edge as it would on screen, without widening everything around it.
struct LeadingOverflowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? ideal.width, height: ideal.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: .unspecified)
    }
}
