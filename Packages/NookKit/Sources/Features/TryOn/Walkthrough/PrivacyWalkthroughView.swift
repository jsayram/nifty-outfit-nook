import DesignSystem
import Models
import SwiftUI

/// 33c: the privacy walkthrough on the loading screen. The drawing and its caption read to
/// VoiceOver as one element that describes every step; Reduce Motion swaps the movement for a
/// simple fade between the same frames; and the caption wraps at any Dynamic Type size. A replay
/// has Skip; the first showing plays through (it is under six seconds and never holds up the
/// picture, which is made behind it).
struct PrivacyWalkthroughView: View {
    /// Owned here, so the sheet redrawing around it (a step changing behind the walkthrough) never
    /// starts it over.
    @State private var model: PrivacyWalkthroughModel
    /// Called with true when it played to the end, false when she skipped it. Not called when the
    /// screen goes away first.
    let finished: (Bool) -> Void

    /// - Parameter beat: where it starts. Only snapshot tests start anywhere but the first beat.
    init(canSkip: Bool, beat: WalkthroughBeat = .yourPhoto, finished: @escaping (Bool) -> Void) {
        _model = State(initialValue: PrivacyWalkthroughModel(canSkip: canSkip, beat: beat))
        self.finished = finished
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.closetIsStillImage) private var isStatic

    var body: some View {
        VStack(spacing: NookSpacing.large) {
            VStack(spacing: NookSpacing.medium) {
                WalkthroughStageView(frame: model.beat.frame, reduceMotion: reduceMotion)
                    .frame(maxWidth: 240)
                Text(WalkthroughText.caption(model.beat))
                    .nookTextStyle(.headline)
                    .foregroundStyle(.nook.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .animation(reduceMotion ? .easeInOut(duration: 0.3) : nil, value: model.beat)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(WalkthroughText.spoken))
            .accessibilityIdentifier("walkthrough")

            Text(TryOnConsentText.underPicture)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.canSkip {
                NookButton(WalkthroughText.skip, kind: .soft, fillsWidth: true) {
                    model.skip()
                    finished(false)
                }
                .accessibilityIdentifier("walkthrough.skip")
            }
        }
        .task {
            // A still image (the snapshot tests) shows the beat it was given and plays nothing.
            if isStatic { return }
            let completed = await model.play()
            if !Task.isCancelled, completed { finished(true) }
        }
    }
}

/// How the figure moves for a frame. With Reduce Motion it never moves or changes size: while the
/// photo is out with the image service it only fades down and the cloud fades in over it. Without,
/// it shrinks and lifts up under the cloud, then comes back.
struct WalkthroughMotion: Equatable {
    var figureOpacity: Double
    var figureScale: CGFloat
    /// How far the figure is lifted, as a share of the picture's height (negative is up).
    var figureLift: CGFloat

    init(frame: WalkthroughFrame, reduceMotion: Bool) {
        guard frame.inCloud else {
            figureOpacity = 1
            figureScale = 1
            figureLift = 0
            return
        }
        if reduceMotion {
            figureOpacity = 0.25
            figureScale = 1
            figureLift = 0
        } else {
            // A small copy of the photo sits under the cloud while it is out.
            figureOpacity = 1
            figureScale = 0.3
            figureLift = -0.14
        }
    }
}

/// The drawing: a figure (never a photo of anyone) in her room, then under a soft veil, then on
/// the studio backdrop, out to the image service and back dressed, then with her face and the
/// "on your phone" lock. Each flag in `WalkthroughFrame` fades in or out; without Reduce Motion
/// the figure also moves to the cloud and back.
struct WalkthroughStageView: View {
    let frame: WalkthroughFrame
    let reduceMotion: Bool

    private var motion: WalkthroughMotion { WalkthroughMotion(frame: frame, reduceMotion: reduceMotion) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                room
                    .opacity(frame.studio ? 0 : 1)
                studio
                    .opacity(frame.studio ? 1 : 0)
                figure(width: width, height: height)
                    .opacity(motion.figureOpacity)
                    .scaleEffect(motion.figureScale)
                    .offset(y: motion.figureLift * height)
                Image(systemName: "cloud.fill")
                    .font(.system(size: width * 0.26))
                    .foregroundStyle(Color.nook.accent)
                    .position(x: width / 2, y: height * 0.16)
                    .opacity(frame.inCloud ? 1 : 0)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: width * 0.1))
                    .foregroundStyle(Color.nook.success)
                    .position(x: width * 0.84, y: height * 0.1)
                    .opacity(frame.checked && !frame.inCloud ? 1 : 0)
                lock(width: width)
                    .position(x: width / 2, y: height * 0.94)
                    .opacity(frame.lock ? 1 : 0)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: NookRadius.group, style: .continuous))
            .animation(reduceMotion ? .easeInOut(duration: 0.45) : .smooth(duration: 0.6), value: frame)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
    }

    // MARK: Backdrops

    /// Her room, drawn as a plain wall and floor with a window.
    private var room: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [.nook.skyTop, .nook.skyBottom], startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.nook.surface.opacity(0.7))
                    .frame(width: proxy.size.width * 0.28, height: proxy.size.height * 0.2)
                    .position(x: proxy.size.width * 0.82, y: proxy.size.height * 0.28)
                Rectangle()
                    .fill(Color.nook.floor)
                    .frame(height: proxy.size.height * 0.22)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.89)
            }
        }
    }

    /// The plain studio backdrop: a soft vertical gradient.
    private var studio: some View {
        LinearGradient(colors: [.nook.backgroundLow, .nook.tintStrong], startPoint: .top, endPoint: .bottom)
    }

    // MARK: The figure

    private func figure(width: CGFloat, height: CGFloat) -> some View {
        let top = frame.dressed ? Color.nook.accent : Color.nook.textSecondary
        let bottom = frame.dressed ? Color.nook.artSageDeep : Color.nook.artStone
        let skin = Color.nook.accent.opacity(0.4)
        return ZStack {
            // Legs and arms, then the top over them.
            ForEach([-1.0, 1.0], id: \.self) { side in
                RoundedRectangle(cornerRadius: width * 0.05)
                    .fill(bottom)
                    .frame(width: width * 0.15, height: height * 0.3)
                    .position(x: width * (0.5 + 0.085 * side), y: height * 0.8)
                RoundedRectangle(cornerRadius: width * 0.035)
                    .fill(skin)
                    .frame(width: width * 0.07, height: height * 0.24)
                    .position(x: width * (0.5 + 0.225 * side), y: height * 0.52)
            }
            RoundedRectangle(cornerRadius: width * 0.07)
                .fill(top)
                .frame(width: width * 0.38, height: height * 0.3)
                .position(x: width / 2, y: height * 0.51)
            Rectangle()
                .fill(skin)
                .frame(width: width * 0.06, height: height * 0.05)
                .position(x: width / 2, y: height * 0.34)
            Circle()
                .fill(skin)
                .frame(width: width * 0.22, height: width * 0.22)
                .position(x: width / 2, y: height * 0.24)
            face(width: width, height: height)
                .opacity(frame.veiled ? 0 : 1)
            // The soft veil: from the neck up, with blurred edges, so the head is covered and
            // never cut off.
            Ellipse()
                .fill(Color.nook.tintStrong)
                .frame(width: width * 0.36, height: height * 0.3)
                .blur(radius: width * 0.03)
                .overlay {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: width * 0.08))
                        .foregroundStyle(Color.nook.textSecondary)
                }
                .position(x: width / 2, y: height * 0.26)
                .opacity(frame.veiled ? 0.97 : 0)
        }
        .frame(width: width, height: height)
    }

    private func face(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle()
                    .fill(Color.nook.textPrimary)
                    .frame(width: width * 0.022, height: width * 0.022)
                    .position(x: width * (0.5 + 0.04 * side), y: height * 0.235)
            }
            Path { path in
                path.addArc(
                    center: CGPoint(x: width / 2, y: height * 0.245), radius: width * 0.045,
                    startAngle: .degrees(30), endAngle: .degrees(150), clockwise: false)
            }
            .stroke(Color.nook.textPrimary, style: StrokeStyle(lineWidth: width * 0.012, lineCap: .round))
        }
    }

    private func lock(width: CGFloat) -> some View {
        Label(WalkthroughText.lock, systemImage: "lock.fill")
            .font(.system(size: width * 0.065, weight: .semibold))
            .foregroundStyle(Color.nook.textPrimary)
            .padding(.horizontal, width * 0.04)
            .padding(.vertical, width * 0.02)
            .background(Color.nook.surface, in: Capsule())
    }
}
