import SwiftUI

extension View {
    /// Marks this view as the spot a tour step points at. The tour follows it wherever it moves:
    /// a rotation, a window resize, a scroll or a change of layout.
    ///
    /// - Parameters:
    ///   - label: what VoiceOver calls the control, read on the tour card and on the spotlight.
    ///   - hint: what activating it from the tour does. Without one, VoiceOver hears "Ends the
    ///     tour."
    ///   - isEnabled: false leaves the view unmarked without changing it, for the items of a list
    ///     where only the first one is the spot (her first look, the first piece in the wash).
    ///   - action: what a tap inside the spotlight does, after the tour ends. Usually the same as
    ///     the control's own action. Without one, the tap only ends the tour.
    func tourAnchor(
        _ id: TourAnchorID, label: String, hint: String? = nil, isEnabled: Bool = true,
        action: (() -> Void)? = nil
    ) -> some View {
        modifier(TourAnchorModifier(id: id, label: label, hint: hint, isEnabled: isEnabled, action: action))
    }

    /// Lets this control take VoiceOver focus when a tour that pointed at `id` closes, so she
    /// carries on from the thing the tour just showed her (PRD §7.8: restore focus).
    func tourFocusTarget(_ id: TourAnchorID) -> some View {
        modifier(TourFocusTargetModifier(id: id))
    }
}

private struct TourAnchorModifier: ViewModifier {
    let id: TourAnchorID
    let label: String
    let hint: String?
    let isEnabled: Bool
    let action: (() -> Void)?

    @Environment(\.tourCenter) private var tours
    @State private var owner = UUID()
    /// The last frame seen, so registering never loses one measured just before it.
    @State private var frame: CGRect?

    /// The scroll ID: the anchor's, or one of the view's own while it isn't the spot.
    private var scrollID: TourAnchorID {
        isEnabled ? id : TourAnchorID("\(id.rawValue)#\(owner.uuidString)")
    }

    func body(content: Content) -> some View {
        if let tours {
            content
                .anchorPreference(key: TourAnchorBounds.self, value: .bounds) { isEnabled ? [id: $0] : [:] }
                // So a scroll view around it can bring it into view (`TourScrollReader`).
                .id(scrollID)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: { frame in
                    self.frame = frame
                    if isEnabled { tours.move(id, owner: owner, to: frame) }
                }
                // Again on every appearance: a screen covered by a pushed one, or on another
                // tab, lost its anchors when it disappeared, and a replay may point at it again.
                .onAppear { register(in: tours) }
                .onChange(of: label) { register(in: tours) }
                .onChange(of: isEnabled) { register(in: tours) }
                .onDisappear { tours.remove(id, owner: owner) }
        } else {
            content
                .anchorPreference(key: TourAnchorBounds.self, value: .bounds) { isEnabled ? [id: $0] : [:] }
        }
    }

    private func register(in tours: TourCenter) {
        guard isEnabled else {
            tours.remove(id, owner: owner)
            return
        }
        tours.register(id, owner: owner, frame: frame, label: label, hint: hint ?? TourText.endsTour, action: action)
    }
}

/// Where each anchored control is, for a still image of a tour: the snapshot tests read it with
/// `overlayPreferenceValue` and draw the spotlight there, in the same layout pass as the page.
/// The app itself uses the frames the anchors report to `TourCenter`.
struct TourAnchorBounds: PreferenceKey {
    static let defaultValue: [TourAnchorID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [TourAnchorID: Anchor<CGRect>], nextValue: () -> [TourAnchorID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct TourFocusTargetModifier: ViewModifier {
    let id: TourAnchorID

    @Environment(\.tourCenter) private var tours
    @AccessibilityFocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if let tours {
            content
                .accessibilityFocused($isFocused)
                .onChange(of: tours.focusRequest) { _, request in
                    guard request?.anchor == id else { return }
                    Task {
                        // The screen under the tour is hidden from VoiceOver until the tour
                        // has gone, so wait a moment before moving focus there.
                        try? await Task.sleep(for: .milliseconds(300))
                        isFocused = true
                    }
                }
        } else {
            content
        }
    }
}

/// Puts a scroll view's anchored controls in view as the tour reaches them, so a step never
/// points at something off screen. Wrap the `ScrollView`. With Reduce Motion the page jumps
/// instead of scrolling. A control that's already wholly on screen is left where it is, so a
/// tour that needs no scrolling never moves the page (S4, 31 October 2026: on Your looks the
/// tour scrolled the page for a control already in view, and the scroll back after Skip put the
/// Saved tab where Review had been, under her finger).
///
/// When the tour ends, however it ends, the page goes back to where it was before the tour
/// moved it, if it did. Left where the last step was, a page could end with its title half under
/// the back button (QA, October 2026: a look, Profile, Delete my data). It goes back at once, as
/// the tour closes, never as a scroll that's still moving once the tour has gone.
struct TourScrollReader<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.tourCenter) private var tours
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var position = ScrollPosition()
    /// How far down the page is scrolled, kept up to date.
    @State private var offset: CGFloat = 0
    /// Where the page was when the tour first moved it, until the tour ends.
    @State private var offsetBeforeTour: CGFloat?
    /// The part of the scroll view she can see, in global coordinates, inside the bars.
    @State private var visibleFrame: CGRect?

    var body: some View {
        if let tours {
            ScrollViewReader { proxy in
                content
                    .scrollPosition($position)
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, offset in
                        self.offset = offset
                    }
                    .onGeometryChange(for: CGRect.self) { geometry in
                        let frame = geometry.frame(in: .global)
                        let insets = geometry.safeAreaInsets
                        return CGRect(
                            x: frame.minX + insets.leading, y: frame.minY + insets.top,
                            width: frame.width - insets.leading - insets.trailing,
                            height: frame.height - insets.top - insets.bottom)
                    } action: { frame in
                        visibleFrame = frame
                    }
                    .onChange(of: tours.currentAnchor, initial: true) { _, anchor in
                        guard let anchor else {
                            restore()
                            return
                        }
                        // Already wholly in view: the page stays put.
                        if let frame = tours.anchors[anchor]?.frame, let visibleFrame,
                            Self.isWhollyVisible(frame, in: visibleFrame)
                        {
                            return
                        }
                        if offsetBeforeTour == nil { offsetBeforeTour = offset }
                        // Near the top, which leaves the most room for the card below it.
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
                            proxy.scrollTo(anchor, anchor: UnitPoint(x: 0.5, y: 0.2))
                        }
                    }
            }
        } else {
            content
        }
    }

    /// Whether a control's frame is all inside the visible part of the scroll view, allowing
    /// half a point for rounding.
    static func isWhollyVisible(_ frame: CGRect, in visible: CGRect) -> Bool {
        !frame.isEmpty && visible.insetBy(dx: -0.5, dy: -0.5).contains(frame)
    }

    /// Puts the page back where it was before the tour, if the tour moved it. At once, with no
    /// animation, so nothing is still moving once the tour has gone.
    private func restore() {
        guard let before = offsetBeforeTour else { return }
        offsetBeforeTour = nil
        guard abs(offset - before) > 1 else { return }
        var instantly = Transaction(animation: nil)
        instantly.disablesAnimations = true
        withTransaction(instantly) {
            if before <= 1 {
                position.scrollTo(edge: .top)
            } else {
                position.scrollTo(y: before)
            }
        }
    }
}
