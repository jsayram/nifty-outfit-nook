import SwiftUI

/// A quick tour over the screen (Phase 16a, PRD §7.8, `home-tour.html`): a warm dim with a soft
/// cut-out around one real control, a warm glow at its edge, and the card beside it with a tail
/// aimed at the control.
///
/// The dim takes every tap, so nothing under it opens by accident. A tap inside the spotlight
/// (or activating it with VoiceOver) calls `onTarget`, which ends the tour and does what the
/// control does. With no `target` the card shows on its own in the middle; when the card can't
/// sit beside the control without covering it (the largest text sizes), it shows on its own at
/// the roomier end. Escape, Skip and the VoiceOver escape gesture call `onSkip`.
///
/// It fills the space it's given and expects to be drawn over the whole screen, under no safe
/// area: pass the screen's safe area as `safeArea` so the card stays clear of the bars. With
/// Reduce Motion on, steps cross-fade instead of the spotlight and card moving.
public struct NookTourOverlay: View {
    let step: NookTourStep
    let target: CGRect?
    let safeArea: EdgeInsets
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void
    let onTarget: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - target: the highlighted control's frame, in this view's own space. `nil` shows the
    ///     card without a spotlight.
    public init(
        step: NookTourStep, target: CGRect?, safeArea: EdgeInsets, onNext: @escaping () -> Void,
        onBack: @escaping () -> Void, onSkip: @escaping () -> Void, onTarget: @escaping () -> Void
    ) {
        self.step = step
        self.target = target
        self.safeArea = safeArea
        self.onNext = onNext
        self.onBack = onBack
        self.onSkip = onSkip
        self.onTarget = onTarget
    }

    /// The card's width before Dynamic Type: the approved 300 points. It grows at larger text
    /// sizes and never gets wider than the screen allows.
    static func cardWidth(for size: DynamicTypeSize) -> CGFloat {
        if size.isAccessibilitySize { return 480 }
        return size > .large ? 340 : 300
    }

    public var body: some View {
        Group {
            if reduceMotion {
                // No movement: each step replaces the last with a cross-fade.
                stage
                    .id(step.index)
                    .transition(.opacity)
            } else {
                stage
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: step.index)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onSkip)
        .accessibilityIdentifier("tour")
    }

    private var stage: some View {
        NookTourLayout(target: target, safeArea: safeArea, cardWidth: Self.cardWidth(for: dynamicTypeSize)) {
            // 0: the card, drawn over the dim. VoiceOver follows drawing order, so the card
            // comes before the control's own button, which is drawn last (they never overlap).
            NookTourCard(step: step, onNext: onNext, onBack: onBack, onSkip: onSkip)
                .zIndex(1)
            // 1: the dim, which takes every tap outside the spotlight.
            Color.nook.tourScrim
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)
            // 2: the cut-out, softened at its edge.
            NookRadius.shape(Self.spotlightRadius)
                .fill(.black)
                .blur(radius: 3)
                .blendMode(.destinationOut)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            // 3: the glow and the soft rim, blurred so there's no hard outline.
            ZStack {
                NookRadius.shape(Self.spotlightRadius)
                    .stroke(Color.nook.tourGlow, lineWidth: 12)
                    .blur(radius: 9)
                NookRadius.shape(Self.spotlightRadius)
                    .stroke(Color.nook.tourRim, lineWidth: 4)
                    .blur(radius: 1.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // 4: the control itself, reachable by touch and by VoiceOver.
            Button(action: onTarget) {
                Color.clear.contentShape(NookRadius.shape(Self.spotlightRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(step.targetLabel ?? "")
            .accessibilityHint(step.targetHint ?? "")
            .accessibilityHidden(step.targetLabel == nil)
            .accessibilityIdentifier("tour.target")
            .zIndex(2)
            // 5: the tail, under the card's edge.
            NookRadius.shape(5)
                .fill(Color.nook.tourCard)
                .frame(width: Self.tailSize, height: Self.tailSize)
                .rotationEffect(.degrees(45))
                .accessibilityHidden(true)
        }
        .compositingGroup()
    }

    /// The spotlight's corners (`.tour-spotlight`, 22 px).
    nonisolated static let spotlightRadius: CGFloat = 22
    /// The tail's square before it's turned 45 degrees (`.tour-card::after`, 22 px).
    nonisolated static let tailSize: CGFloat = 22
}

/// Places the dim, the spotlight, the tail and the card. The card's height depends on its words
/// and the text size, so the card is measured here, inside layout, and the spotlight and tail
/// follow where it lands. Parts that aren't shown (no spotlight, no tail) go far off screen.
struct NookTourLayout: Layout {
    let target: CGRect?
    let safeArea: EdgeInsets
    let cardWidth: CGFloat

    /// Clear of the screen's edges and bars.
    static let margin: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 6 else { return }
        let placement = Self.placement(
            in: bounds, safeArea: safeArea, target: target, cardWidth: cardWidth, card: subviews[0])
        let hidden = CGPoint(x: bounds.minX - 10_000, y: bounds.minY - 10_000)

        subviews[0].place(at: placement.card.origin, proposal: ProposedViewSize(placement.card.size))
        subviews[1].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        for index in 2...4 {
            if let spot = placement.spotlight {
                subviews[index].place(at: spot.origin, proposal: ProposedViewSize(spot.size))
            } else {
                subviews[index].place(at: hidden, proposal: .zero)
            }
        }
        if let edge = placement.tailEdge, let position = placement.tailPosition {
            // The tail's middle sits on the card's edge, so half of it sticks out.
            let card = placement.card
            let center: CGPoint =
                switch edge {
                case .top: CGPoint(x: position, y: card.minY)
                case .bottom: CGPoint(x: position, y: card.maxY)
                case .leading: CGPoint(x: card.minX, y: position)
                case .trailing: CGPoint(x: card.maxX, y: position)
                }
            let size = NookTourOverlay.tailSize
            subviews[5].place(at: center, anchor: .center, proposal: ProposedViewSize(width: size, height: size))
        } else {
            subviews[5].place(at: hidden, proposal: .zero)
        }
    }

    /// Where the card and the spotlight go in `bounds`: the card measured at its width, cut to
    /// the screen's height (its words then scroll), and placed by `NookTourPlacement`.
    static func placement(
        in bounds: CGRect, safeArea: EdgeInsets, target: CGRect?, cardWidth: CGFloat, card: LayoutSubview
    ) -> NookTourPlacement {
        let area = CGRect(
            x: bounds.minX + safeArea.leading + margin,
            y: bounds.minY + safeArea.top + margin,
            width: max(0, bounds.width - safeArea.leading - safeArea.trailing - margin * 2),
            height: max(0, bounds.height - safeArea.top - safeArea.bottom - margin * 2))
        let width = min(cardWidth, area.width)
        let height = card.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let size = CGSize(width: width, height: min(height, area.height))
        let shifted = target.map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) }
        return NookTourPlacement.place(card: size, target: shifted, in: area)
    }
}
