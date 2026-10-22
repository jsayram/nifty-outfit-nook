import DesignSystem
import Models
import SwiftUI

/// The try-on photo's camera (Phase 33b): a full-screen viewfinder with an outline to stand in, a
/// hint that changes as she moves ("Step back a little", "A bit more light would help"), and a
/// timer that takes the photo by itself once she's in place. The shutter is always there too.
///
/// The picture is shown whole, 3 wide to 4 tall, so what she sees is what is looked at and what is
/// photographed. The photo goes on to the same intake as any photo (`PhotoIntake.keep`, which
/// strips its metadata) and to the check before she saves it; nothing here keeps it.
struct TryOnCaptureScreen: View {
    @State private var model: TryOnCaptureModel
    let photoTaken: PhotoTaken
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.closetIsStillImage) private var isStillImage

    /// `makeModel` runs each time the screen's owner redraws, and only the first is kept: building a
    /// model must stay cheap and must not start the camera (`run` does that).
    init(makeModel: () -> TryOnCaptureModel, photoTaken: @escaping PhotoTaken, close: @escaping () -> Void) {
        _model = State(initialValue: makeModel())
        self.photoTaken = photoTaken
        self.close = close
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: NookSpacing.medium) {
            topBar
            if dynamicTypeSize.isAccessibilitySize {
                // Large text needs room: the picture and the hint scroll, and the timer switch and
                // the shutter stay in reach below.
                if isStillImage {
                    // ImageRenderer draws a scroll view's content as nothing.
                    VStack(spacing: NookSpacing.medium) {
                        viewfinder
                        hint
                    }
                } else {
                    ScrollView {
                        VStack(spacing: NookSpacing.medium) {
                            viewfinder
                            hint
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                viewfinder
                hint
            }
            controls
        }
        .padding(.horizontal, NookSpacing.large)
        .padding(.vertical, NookSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await model.run(photoTaken: photoTaken) }
        .onDisappear { model.stop() }
        .onChange(of: model.coach.advice) { _, new in
            guard !isStillImage, new != .starting else { return }
            AccessibilityNotification.Announcement(TryOnSetupText.guidance(new)).post()
        }
        .onChange(of: model.coach.countdown) { old, new in
            guard !isStillImage, old == nil, let new else { return }
            AccessibilityNotification.Announcement(TryOnSetupText.countdown(new)).post()
        }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.white.opacity(0.18)))
            }
            .accessibilityLabel(Text(TryOnSetupText.close))
            .accessibilityIdentifier("tryOnCapture.close")
            Spacer()
            if model.source.canFlip {
                Button {
                    Task { await model.source.flip() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.white.opacity(0.18)))
                }
                .accessibilityLabel(Text(TryOnSetupText.flip))
                .accessibilityIdentifier("tryOnCapture.flip")
            }
        }
    }

    private var viewfinder: some View {
        ZStack {
            Color(white: 0.08)
            switch model.phase {
            case .unavailable:
                Text(TryOnSetupText.cameraDidNotStart)
                    .nookTextStyle(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(NookSpacing.large)
            default:
                model.source.preview()
                BodyOutline()
                    .stroke(
                        model.advice == .ready && !model.guidanceIsOff ? Self.ready : Color.white.opacity(0.8),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [8, 7])
                    )
                    .accessibilityHidden(true)
                if let count = model.coach.countdown, model.takesItself {
                    Text("\(count)")
                        .font(.system(size: 96, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        // The live picture shows her: covered in the app switcher, like her photos (SECURITY_STANDARD §4).
        .hiddenWhenInactive()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.coach.countdown)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Text("Camera view", bundle: .module, comment: "VoiceOver: the try-on camera's picture")
        )
    }

    private var hint: some View {
        let advice = model.advice
        let isReady = advice == .ready && !model.guidanceIsOff
        return VStack(spacing: NookSpacing.small) {
            HStack(spacing: NookSpacing.medium) {
                Image(systemName: model.guidanceIsOff ? "hand.tap" : TryOnSetupText.symbol(advice))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isReady ? Color.nook.success : Color.nook.accent)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                Text(model.guidanceIsOff ? TryOnSetupText.guidanceOff : TryOnSetupText.guidance(advice))
                    .nookTextStyle(.headline)
                    .foregroundStyle(.nook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(NookSpacing.medium)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isReady ? Color.nook.successSurface : Color.nook.surface)
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("tryOnCapture.hint")
            Text(TryOnSetupText.cameraTip)
                .nookTextStyle(.note)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timerLabel: some View {
        Text(TryOnSetupText.takesItself)
            .nookTextStyle(.label)
            .foregroundStyle(.white)
    }

    /// White to start with, and a clear green once she's in place. Fixed colours, since the
    /// viewfinder is a camera picture, dark or light, whatever the app's appearance.
    private static let ready = Color(red: 0.55, green: 0.9, blue: 0.65)

    private var controls: some View {
        VStack(spacing: NookSpacing.medium) {
            if model.phase == .failed {
                Text(TryOnSetupText.photoFailed)
                    .nookTextStyle(.note)
                    .foregroundStyle(.white)
            }
            Group {
                if isStillImage {
                    // ImageRenderer can't draw the system switch.
                    HStack {
                        timerLabel
                        Spacer()
                        DrawnSwitch(isOn: model.takesItself)
                    }
                } else {
                    Toggle(isOn: $model.takesItself) { timerLabel }
                        .tint(Color.nook.accent)
                        .disabled(model.guidanceIsOff)
                        .accessibilityIdentifier("tryOnCapture.timer")
                }
            }
            Button {
                Task { await model.take(photoTaken) }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 72, height: 72)
                    Circle().fill(.white).frame(width: 58, height: 58)
                }
            }
            .disabled(model.phase == .starting || model.phase == .taking || model.phase == .unavailable)
            .opacity(model.phase == .running || model.phase == .failed ? 1 : 0.4)
            .accessibilityLabel(Text(TryOnSetupText.shutter))
            .accessibilityIdentifier("tryOnCapture.shutter")
        }
    }
}
