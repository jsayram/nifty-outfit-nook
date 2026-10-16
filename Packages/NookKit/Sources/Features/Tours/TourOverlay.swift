import DesignSystem
import SwiftUI

/// Draws the tour that's showing over the whole window (`NookTourOverlay`), with the spotlight
/// on the current step's anchored control. The root view puts it over the tab view.
///
/// A control that isn't on screen (not there in this layout, or scrolled under a bar) gets no
/// spotlight: the card shows on its own and still says what it's about.
struct TourOverlay: View {
    let tours: TourCenter

    var body: some View {
        GeometryReader { safe in
            let insets = safe.safeAreaInsets
            GeometryReader { full in
                if let active = tours.active {
                    let origin = full.frame(in: .global).origin
                    let anchor = tours.anchors[active.step.anchor]
                    let frame = anchor?.frame?.offsetBy(dx: -origin.x, dy: -origin.y)
                    NookTourOverlay(
                        step: NookTourStep(
                            title: active.step.title,
                            message: active.step.message,
                            index: active.run.index,
                            count: active.run.stepCount,
                            finishTitle: active.definition.finishTitle,
                            targetLabel: anchor?.label,
                            targetHint: anchor?.hint),
                        target: frame.flatMap { Self.visible($0, in: full.size, insets: insets) },
                        safeArea: insets,
                        onNext: tours.next,
                        onBack: tours.back,
                        onSkip: tours.skip,
                        onTarget: tours.activateTarget
                    )
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(tours.isShowing)
        .animation(.easeInOut(duration: 0.2), value: tours.isShowing)
    }

    /// The control's frame when enough of it is on screen to point at, inside the safe area:
    /// at least half its height and width, or 22 points of each for a big one.
    static func visible(_ frame: CGRect, in size: CGSize, insets: EdgeInsets) -> CGRect? {
        let area = CGRect(
            x: insets.leading, y: insets.top,
            width: size.width - insets.leading - insets.trailing,
            height: size.height - insets.top - insets.bottom)
        let shown = frame.intersection(area)
        guard !shown.isNull,
            shown.height >= min(frame.height, 44) / 2,
            shown.width >= min(frame.width, 44) / 2
        else { return nil }
        return frame
    }
}
