import SwiftUI

/// What one step of a quick tour says (Phase 16a, PRD §7.8). The words come in already
/// localized.
nonisolated public struct NookTourStep: Hashable, Sendable {
    public var title: String
    public var message: String
    /// The step on screen, from 0.
    public var index: Int
    public var count: Int
    /// The last step's button, which names what to do next ("Start styling" on Home).
    public var finishTitle: String
    /// What VoiceOver calls the highlighted control, such as "Laptop: Style Me".
    public var targetLabel: String?
    /// What activating the highlighted control from the tour does, read after its label.
    public var targetHint: String?

    public init(
        title: String, message: String, index: Int, count: Int, finishTitle: String, targetLabel: String? = nil,
        targetHint: String? = nil
    ) {
        self.title = title
        self.message = message
        self.index = index
        self.count = count
        self.finishTitle = finishTitle
        self.targetLabel = targetLabel
        self.targetHint = targetHint
    }

    public var isFirst: Bool { index == 0 }
    public var isLast: Bool { index >= count - 1 }
}

/// The card of a quick tour (`.tour-card` in `home-tour.html`): sparkles and "Quick tour · 1 of
/// 4", the title, a sentence or two, progress dots, then Back (after the first step), Skip and
/// Next. No outline: the plate colour on the dim with a soft shadow below.
///
/// It reflows with Dynamic Type: the buttons drop under the dots when they don't fit beside
/// them, and stack at full width at the largest sizes. The card's words are one VoiceOver
/// element, read first ("Quick tour, step 1 of 4. Style Me. ..."), and VoiceOver moves to it on
/// every step. Next answers Return and Skip answers Escape on a hardware keyboard.
public struct NookTourCard: View {
    let step: NookTourStep
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    @Environment(\.nookStaticRendering) private var isStatic

    public init(
        step: NookTourStep, onNext: @escaping () -> Void, onBack: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.step = step
        self.onNext = onNext
        self.onBack = onBack
        self.onSkip = onSkip
    }

    /// The card's corners (`.tour-card`, 26 px).
    public static let cornerRadius: CGFloat = 26

    public var body: some View {
        let shape = NookRadius.shape(Self.cornerRadius)
        VStack(alignment: .leading, spacing: 0) {
            // Taller than the screen at the largest sizes: the words scroll inside the card,
            // and the buttons stay put below them.
            ViewThatFits(in: .vertical) {
                words
                scrollingWords
            }
            NookTourControls(step: step, onNext: onNext, onBack: onBack, onSkip: onSkip)
                .padding(.top, NookSpacing.medium)
                // Measured first, so the words get what's left.
                .layoutPriority(1)
        }
        .padding(.top, NookSpacing.large)
        .padding(.leading, 18)
        .padding(.trailing, NookSpacing.large)
        .padding(.bottom, NookSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { shape.fill(Color.nook.tourCard) }
        .softShadow(.dropLarge, in: shape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.card")
    }

    /// The words in a scroll view, when they're taller than the card can be. Its indicator
    /// flashes as each step appears, and the last line fades out while there's more below, so
    /// it's clear the words go on (QA, October 2026: at AX5 the card ended on "something you"
    /// with nothing to say "own." was below).
    @ViewBuilder private var scrollingWords: some View {
        if isStatic {
            // A still image can't scroll: the words are cut where the scroll view would end.
            words
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()
                .modifier(MoreBelowFade(isMoreBelow: true))
        } else {
            TourScrollingWords(words: words)
                // Each step starts at the top, and flashes the indicator again.
                .id(step.index)
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "sparkles")
                Text(
                    "Quick tour · \(step.index + 1) of \(step.count)", bundle: .module,
                    comment: "Over a quick tour's title: which step this is, as in Quick tour · 1 of 4")
            }
            .nookTextStyle(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.nook.accent)
            Text(step.title)
                .nookTextStyle(.title)
                .foregroundStyle(.nook.textPrimary)
                .padding(.top, 6)
            Text(step.message)
                .nookTextStyle(.body)
                .foregroundStyle(.nook.textSecondary)
                .padding(.top, NookSpacing.xSmall)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenWords(for: step))
        .accessibilityIdentifier("tour.text")
        .modifier(TourFocus(step: step.index, isStatic: isStatic))
    }

    /// What VoiceOver reads for the card's words: the step, the title, the message, and the
    /// control it points at.
    static func spokenWords(for step: NookTourStep) -> String {
        let count = String(
            localized: "Quick tour, step \(step.index + 1) of \(step.count)", bundle: .module,
            comment: "VoiceOver: which step of a quick tour this is")
        var parts = [count, step.title, step.message]
        if let target = step.targetLabel {
            parts.append(
                String(
                    localized: "Highlighted: \(target)", bundle: .module,
                    comment: "VoiceOver: the control a quick tour step points at, as in Highlighted: Laptop: Style Me"))
        }
        return parts.map(sentence).joined(separator: " ")
    }

    /// Ends `text` with a full stop unless it already ends a sentence.
    private static func sentence(_ text: String) -> String {
        guard let last = text.last, !".!?…".contains(last) else { return text }
        return text + "."
    }
}

/// The card's words in a scroll view that fades its last line while more is below.
private struct TourScrollingWords<Words: View>: View {
    let words: Words

    @State private var isMoreBelow = true

    var body: some View {
        ScrollView { words }
            .scrollIndicators(.visible)
            .scrollIndicatorsFlash(onAppear: true)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    < geometry.contentSize.height + geometry.contentInsets.bottom - 1
            } action: { _, moreBelow in
                isMoreBelow = moreBelow
            }
            .modifier(MoreBelowFade(isMoreBelow: isMoreBelow))
    }
}

/// Fades the bottom of the words out while there's more of them below.
private struct MoreBelowFade: ViewModifier {
    let isMoreBelow: Bool

    @ScaledMetric(relativeTo: .body) private var fadeHeight: CGFloat = 36

    func body(content: Content) -> some View {
        content.mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(
                    colors: [.black, isMoreBelow ? .clear : .black], startPoint: .top, endPoint: .bottom
                )
                .frame(height: fadeHeight)
            }
        }
    }
}

/// Moves VoiceOver to the card's words when a step appears. Not in still images, where
/// `ImageRenderer` draws an `.accessibilityFocused` view as empty space.
private struct TourFocus: ViewModifier {
    let step: Int
    let isStatic: Bool

    @AccessibilityFocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if isStatic {
            content
        } else {
            content
                .accessibilityFocused($isFocused)
                .task(id: step) {
                    // A moment, so the card is on screen before VoiceOver is sent to it.
                    try? await Task.sleep(for: .milliseconds(150))
                    isFocused = true
                }
        }
    }
}

/// The dots and the buttons. Beside each other when they fit, the buttons under the dots when
/// they don't, and full-width buttons stacked at the largest sizes.
private struct NookTourControls: View {
    let step: NookTourStep
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NookSpacing.small) {
                dots
                Spacer(minLength: 0)
                back
                skip()
                next()
            }
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                dots
                HStack(spacing: NookSpacing.small) {
                    Spacer(minLength: 0)
                    back
                    skip()
                    next()
                }
            }
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                dots
                next(fillsWidth: true)
                HStack(spacing: NookSpacing.small) {
                    back
                    skip(fillsWidth: true)
                }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<step.count, id: \.self) { index in
                Capsule()
                    .fill(index == step.index ? Color.nook.accent : Color.nook.track)
                    .frame(width: index == step.index ? 20 : 7, height: 7)
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    @ViewBuilder private var back: some View {
        if !step.isFirst {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 28)
            }
            .buttonStyle(.nook(.text))
            .accessibilityLabel(Text("Back", bundle: .module, comment: "Quick tour: goes to the step before"))
            .accessibilityIdentifier("tour.back")
        }
    }

    private func skip(fillsWidth: Bool = false) -> some View {
        Button(action: onSkip) {
            Text("Skip", bundle: .module, comment: "Quick tour: ends the tour")
                .fixedSize()
                .foregroundStyle(.nook.textSecondary)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.nook(.text))
        .keyboardShortcut(.cancelAction)
        .accessibilityHint(
            Text("Ends the tour. It won’t start again by itself.", bundle: .module, comment: "VoiceOver hint on Skip")
        )
        .accessibilityIdentifier("tour.skip")
    }

    private func next(fillsWidth: Bool = false) -> some View {
        Button(action: onNext) {
            HStack(spacing: 6) {
                if step.isLast {
                    Text(step.finishTitle)
                } else {
                    Text("Next", bundle: .module, comment: "Quick tour: goes to the next step")
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .fixedSize()
            .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.nook(.primary, size: .small))
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("tour.next")
    }
}
