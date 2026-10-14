import SwiftUI

/// Three soft dots that pulse one after another, for "something is happening".
///
/// With Reduce Motion on, the dots only fade; they don't grow. The indicator is one
/// VoiceOver element that reads "Loading" (or the label you give it).
public struct NookLoadingIndicator: View {
    nonisolated public enum Size: Sendable {
        /// Inside a button, beside its title.
        case small
        /// On a loading screen.
        case large
    }

    private let size: Size
    private let label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nookStaticRendering) private var isStatic
    @ScaledMetric(relativeTo: .body) private var largeDot: CGFloat = 10
    @ScaledMetric(relativeTo: .callout) private var smallDot: CGFloat = 6

    /// - Parameter label: What VoiceOver reads, already localized. Defaults to "Loading".
    public init(size: Size = .large, label: String? = nil) {
        self.size = size
        self.label = label
    }

    public var body: some View {
        Group {
            if isStatic {
                dots(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    dots(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(
            label.map { Text($0) } ?? Text("Loading", bundle: .module, comment: "Spoken while something loads")
        )
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var dotSize: CGFloat { size == .large ? largeDot : smallDot }

    private func dots(at time: TimeInterval) -> some View {
        HStack(spacing: dotSize * 0.7) {
            ForEach(0..<3, id: \.self) { index in
                let wave = pulse(at: time, index: index)
                Circle()
                    .fill(size == .large ? AnyShapeStyle(Color.nook.accent) : AnyShapeStyle(.foreground))
                    .frame(width: dotSize, height: dotSize)
                    .opacity(0.35 + 0.65 * wave)
                    .scaleEffect(reduceMotion ? 1 : 0.75 + 0.25 * wave)
            }
        }
    }

    /// 0 to 1 and back once every 1.2 seconds, each dot a third of a beat behind the one before.
    private func pulse(at time: TimeInterval, index: Int) -> Double {
        let period = 1.2
        let phase = (time / period - Double(index) / 3).truncatingRemainder(dividingBy: 1)
        return 0.5 - 0.5 * cos(2 * .pi * phase)
    }
}
