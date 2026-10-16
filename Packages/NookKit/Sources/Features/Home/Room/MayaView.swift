import DesignSystem
import SwiftUI

/// The three z's that rise from Maya while she sleeps (`maya-zzz.svg`, RD-12).
///
/// They're drawn here rather than in the asset catalog so they take the accent colour, which
/// stays readable on the rug in dark appearance, and so each one can drift on its own. They
/// slowly float up and fade a little, one after another. With Reduce Motion on they stay
/// still in their resting places, and still show. Decorative: hidden from VoiceOver, no taps.
struct SleepyZs: View {
    /// Points per stage unit, so the strokes scale with the room.
    let scale: CGFloat
    /// False under Reduce Motion, and in still images.
    let animates: Bool

    var body: some View {
        Group {
            if animates {
                // A slow drift needs few frames: about a point a second.
                TimelineView(.animation(minimumInterval: 1.0 / 15)) { context in
                    letters(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                letters(at: nil)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func letters(at time: TimeInterval?) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(SleepyZ.all) { letter in
                let drift = time.map { letter.drift(at: $0) } ?? .rest
                letter.shape
                    .stroke(
                        Color.nook.accent,
                        style: StrokeStyle(lineWidth: letter.lineWidth * scale, lineCap: .round, lineJoin: .round)
                    )
                    .opacity(letter.opacity * drift.fade)
                    .offset(x: drift.x * scale, y: drift.y * scale)
            }
        }
    }
}

/// One z of the three, in the 40 x 40 units of `maya-zzz.svg`.
nonisolated struct SleepyZ: Identifiable, Sendable {
    let id: Int
    /// The z's corners: top left, top right, bottom left, bottom right.
    let top: (left: CGPoint, right: CGPoint)
    let bottom: (left: CGPoint, right: CGPoint)
    /// Each z tilts back by 10 degrees around its own centre.
    let centre: CGPoint
    let lineWidth: CGFloat
    /// Smaller and stronger near Maya, larger and fainter as they rise.
    let opacity: Double

    /// The three z's, from the one nearest Maya.
    static let all = [
        SleepyZ(
            id: 0, top: (CGPoint(x: 2.5, y: 31), CGPoint(x: 8, y: 31)),
            bottom: (CGPoint(x: 2.5, y: 36.5), CGPoint(x: 8, y: 36.5)),
            centre: CGPoint(x: 5.25, y: 33.75), lineWidth: 1.6, opacity: 0.75),
        SleepyZ(
            id: 1, top: (CGPoint(x: 12.5, y: 18.5), CGPoint(x: 20.5, y: 18.5)),
            bottom: (CGPoint(x: 12.5, y: 26.5), CGPoint(x: 20.5, y: 26.5)),
            centre: CGPoint(x: 16.5, y: 22.5), lineWidth: 1.8, opacity: 0.55),
        SleepyZ(
            id: 2, top: (CGPoint(x: 25, y: 3.5), CGPoint(x: 36, y: 3.5)),
            bottom: (CGPoint(x: 25, y: 14.5), CGPoint(x: 36, y: 14.5)),
            centre: CGPoint(x: 30.5, y: 9), lineWidth: 2, opacity: 0.38),
    ]

    /// How far one z has drifted from its resting place, in stage units.
    struct Drift: Equatable, Sendable {
        var x: CGFloat
        var y: CGFloat
        /// Multiplies the z's opacity.
        var fade: Double

        static let rest = Drift(x: 0, y: 0, fade: 1)
    }

    /// One slow breath: up and back in seven seconds, as in the mockup's `mayaZ` animation.
    static let period: TimeInterval = 7

    /// The drift at `time` (seconds). Each z runs a little behind the one below it, so they
    /// seem to rise one after another. At most 1.5 units right, 3 up, and 20% fainter.
    func drift(at time: TimeInterval) -> Drift {
        let phase = (time / Self.period + Double(id) * 0.18) * 2 * .pi
        let lift = (1 - cos(phase)) / 2
        return Drift(x: 1.5 * lift, y: -3 * lift, fade: 1 - 0.2 * lift)
    }

    /// The z as a shape that fills a 40 x 40 frame.
    var shape: SleepyZShape { SleepyZShape(letter: self) }
}

struct SleepyZShape: Shape {
    let letter: SleepyZ

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: letter.top.left)
        path.addLine(to: letter.top.right)
        path.addLine(to: letter.bottom.left)
        path.addLine(to: letter.bottom.right)
        let tilt = CGAffineTransform(translationX: letter.centre.x, y: letter.centre.y)
            .rotated(by: -10 * .pi / 180)
            .translatedBy(x: -letter.centre.x, y: -letter.centre.y)
        let fit = CGAffineTransform(scaleX: rect.width / 40, y: rect.height / 40)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return path.applying(tilt.concatenating(fit))
    }
}
