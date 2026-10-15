import DesignSystem
import SwiftUI

extension View {
    /// Covers the view while the app isn't active, so the app switcher's snapshot never holds what
    /// it shows (SECURITY_STANDARD §4: measurements, photos of her, try-on pictures).
    ///
    /// iOS takes that snapshot as the scene stops being active, so the cover goes up on
    /// `.inactive` too, which also hides it behind Control Center and system alerts. Snapshot tests
    /// set `scenePhase` to draw either state.
    func hiddenWhenInactive() -> some View {
        modifier(HiddenWhenInactive())
    }
}

private struct HiddenWhenInactive: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let hidden = scenePhase != .active
        content
            // Hidden from VoiceOver too, so nothing reads the values out from under the cover.
            .accessibilityHidden(hidden)
            .overlay {
                if hidden {
                    ZStack {
                        Color.nook.wallGradient
                        VStack(spacing: NookSpacing.small) {
                            Image(systemName: "eye.slash")
                                .font(.title2.weight(.semibold))
                                .accessibilityHidden(true)
                            Text(FitText.hidden)
                                .nookTextStyle(.note)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.nook.textSecondary)
                        .padding(NookSpacing.xLarge)
                    }
                    // Under the bars too: iOS 26's bars blur the scroll view's content behind
                    // them, and the app switcher's snapshot showed it there.
                    .ignoresSafeArea()
                    .accessibilityIdentifier("hiddenWhenInactive")
                }
            }
    }
}
