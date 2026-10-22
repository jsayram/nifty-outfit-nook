import Foundation
import Models
import SwiftUI
import Testing
import UIKit

@testable import Features

/// A camera for tests: says what it's told to see, and "takes" the bytes it's given.
@MainActor
final class ScriptedFrameSource: TryOnFrameSource {
    var givesGuidance = true
    var canFlip = false
    var starts = true
    var photo: Data? = Data("drawn stand-in".utf8)
    private(set) var stopped = false
    private(set) var photosTaken = 0
    let observations: AsyncStream<FramingObservation?>
    private let continuation: AsyncStream<FramingObservation?>.Continuation

    init() {
        (observations, continuation) = AsyncStream.makeStream()
    }

    func start() async -> Bool { starts }
    func stop() { stopped = true }
    func flip() async {}

    func takePhoto() async -> Data? {
        photosTaken += 1
        return photo
    }

    func preview() -> AnyView {
        AnyView(Image(uiImage: DrawnPersonProvider.image).resizable().scaledToFill())
    }
}

/// What `take` handed over.
@MainActor
final class Taken {
    var photos: [Data] = []
    var count: Int { photos.count }
}

/// Phase 33b: the try-on camera's state, with fake frames and a clock of our own, so the hints,
/// the countdown and the photo can be checked without a camera.
@MainActor
struct TryOnCaptureModelTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let source = ScriptedFrameSource()

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func model(source: ScriptedFrameSource? = nil, phase: TryOnCaptureModel.Phase = .running)
        -> TryOnCaptureModel
    {
        TryOnCaptureModel(source: source ?? self.source, phase: phase)
    }

    private let good = FramingObservation(
        people: 1,
        joints: [
            .nose: .init(x: 0.5, y: 0.12), .leftEye: .init(x: 0.48, y: 0.11), .rightEye: .init(x: 0.52, y: 0.11),
            .neck: .init(x: 0.5, y: 0.2), .leftShoulder: .init(x: 0.4, y: 0.22), .rightShoulder: .init(x: 0.6, y: 0.22),
            .leftWrist: .init(x: 0.28, y: 0.58), .rightWrist: .init(x: 0.72, y: 0.58),
            .leftHip: .init(x: 0.44, y: 0.54), .rightHip: .init(x: 0.56, y: 0.54),
            .leftAnkle: .init(x: 0.44, y: 0.92), .rightAnkle: .init(x: 0.56, y: 0.92),
        ], outline: CGRect(x: 0.3, y: 0.08, width: 0.4, height: 0.86))

    private var cutOff: FramingObservation {
        var seen = good
        seen.outline = CGRect(x: 0.3, y: 0.0, width: 0.4, height: 1.0)
        return seen
    }

    @Test func hintsFollowTheFramesOnceTwoAgree() {
        let model = model()
        #expect(model.advice == .starting)
        model.receive(cutOff, at: at(0))
        model.receive(cutOff, at: at(0.2))
        #expect(model.advice == .stepBack)
        model.receive(good, at: at(0.4))
        model.receive(good, at: at(0.6))
        #expect(model.advice == .ready)
    }

    @Test func goodFramingTakesThePhotoByItselfAfterTheCountdown() async {
        let model = model()
        let taken = Taken()
        model.receive(good, at: at(0))
        model.receive(good, at: at(0.2))
        #expect(!model.tick(at: at(1.5)))
        #expect(model.coach.countdown == 3)
        #expect(model.tick(at: at(4.4)))
        await model.take { taken.photos.append($0) }
        #expect(taken.photos == [Data("drawn stand-in".utf8)])
        #expect(source.photosTaken == 1 && source.stopped)
    }

    @Test func withTheTimerOffNothingIsTakenUntilTheShutter() async {
        let model = model()
        model.takesItself = false
        model.receive(good, at: at(0))
        model.receive(good, at: at(0.2))
        #expect(!model.tick(at: at(30)))
        let taken = Taken()
        await model.take { taken.photos.append($0) }
        #expect(taken.count == 1)
    }

    @Test func turningTheTimerBackOnStartsFresh() {
        let model = model()
        model.takesItself = false
        model.receive(good, at: at(0))
        model.receive(good, at: at(0.2))
        model.takesItself = true
        // Not ready for long enough yet: the old good frames don't count.
        #expect(!model.tick(at: at(30)))
        #expect(model.advice == .starting)
    }

    @Test func aPhotoThatDidntComeOutCanBeTriedAgain() async {
        let model = model()
        source.photo = nil
        let taken = Taken()
        await model.take { taken.photos.append($0) }
        #expect(taken.count == 0 && model.phase == .failed && !source.stopped)
        source.photo = Data("second try".utf8)
        await model.take { taken.photos.append($0) }
        #expect(taken.count == 1)
    }

    @Test func framesThatCantBeLookedAtTurnTheHintsOffAndLeaveTheShutter() {
        let model = model()
        for index in 0..<TryOnCaptureModel.missesBeforeOff { model.receive(nil, at: at(Double(index))) }
        #expect(model.guidanceIsOff)
        #expect(!model.tick(at: at(60)))
        // A frame that works brings them back.
        model.receive(good, at: at(10))
        #expect(!model.guidanceIsOff)
    }

    @Test func aCameraWithNothingLookingAtItsFramesStartsWithHintsOff() {
        let blind = ScriptedFrameSource()
        blind.givesGuidance = false
        #expect(model(source: blind).guidanceIsOff)
    }

    @Test func aCameraThatWontStartSaysSo() async {
        let broken = ScriptedFrameSource()
        broken.starts = false
        let model = model(source: broken, phase: .starting)
        await model.run { _ in }
        #expect(model.phase == .unavailable)
    }

    @Test func nothingHappensBeforeTheCameraIsRunning() async {
        let model = model(phase: .starting)
        model.receive(good, at: at(0))
        model.receive(good, at: at(0.2))
        #expect(model.advice == .starting)
        let taken = Taken()
        await model.take { taken.photos.append($0) }
        #expect(taken.count == 0 && source.photosTaken == 0)
    }
}
