import CoreGraphics
import Foundation
import Testing

@testable import Models

/// Phase 33b: the rules behind the try-on camera's hints and the tips after a photo is checked.
/// Every case is a made-up observation (joints and an outline as shares of the frame), so no
/// camera, no Vision and no photo of anyone is involved.
struct FramingGuidanceTests {
    typealias Joint = FramingObservation.Joint

    /// Someone standing in the middle, facing the camera, arms a little away from her body: the
    /// framing try-on wants. Each test changes one thing.
    static func standing(
        armsOut: Bool = true, faceFound: Bool = true, shoulderHalf: Double = 0.1, anklesSeen: Bool = true,
        centerX: Double = 0.5, top: Double = 0.08, bottom: Double = 0.94, frame: Double = 0.55,
        subject: Double? = 0.55, people: Int = 1
    ) -> FramingObservation {
        func point(_ x: Double, _ y: Double, _ confidence: Double = 1) -> FramingObservation.Point {
            .init(x: x, y: y, confidence: confidence)
        }
        let reach = armsOut ? 0.22 : 0.09
        var joints: [Joint: FramingObservation.Point] = [
            .neck: point(centerX, 0.2),
            .leftShoulder: point(centerX - shoulderHalf, 0.22), .rightShoulder: point(centerX + shoulderHalf, 0.22),
            .leftElbow: point(centerX - reach - 0.02, 0.38), .rightElbow: point(centerX + reach + 0.02, 0.38),
            .leftWrist: point(centerX - reach, 0.58), .rightWrist: point(centerX + reach, 0.58),
            .leftHip: point(centerX - 0.06, 0.54), .rightHip: point(centerX + 0.06, 0.54),
            .leftKnee: point(centerX - 0.06, 0.74), .rightKnee: point(centerX + 0.06, 0.74),
        ]
        if faceFound {
            joints[.nose] = point(centerX, 0.12)
            joints[.leftEye] = point(centerX - 0.02, 0.11)
            joints[.rightEye] = point(centerX + 0.02, 0.11)
        }
        if anklesSeen {
            joints[.leftAnkle] = point(centerX - 0.06, bottom - 0.02)
            joints[.rightAnkle] = point(centerX + 0.06, bottom - 0.02)
        }
        return FramingObservation(
            people: people, joints: joints,
            outline: CGRect(x: centerX - 0.2, y: top, width: 0.4, height: bottom - top), frameBrightness: frame,
            subjectBrightness: subject)
    }

    // MARK: Good framing

    @Test func goodFramingIsReady() {
        #expect(FramingGuidance.issues(in: Self.standing()).isEmpty)
        #expect(FramingGuidance.advice(for: Self.standing()) == .ready)
    }

    @Test func noFrameYetIsStarting() {
        #expect(FramingGuidance.advice(for: nil) == .starting)
    }

    // MARK: Whole body

    @Test func noOneInViewSaysSo() {
        #expect(FramingGuidance.advice(for: FramingObservation(people: 0)) == .noOneInView)
    }

    @Test func noOneInADarkFrameAsksForLight() {
        #expect(FramingGuidance.advice(for: FramingObservation(people: 0, frameBrightness: 0.1)) == .moreLight)
    }

    @Test func feetCutOffMeansStepBack() {
        #expect(FramingGuidance.advice(for: Self.standing(anklesSeen: false, bottom: 0.9)) == .stepBack)
        // Her outline runs to the bottom edge, so her feet are past it even if a joint was guessed.
        #expect(FramingGuidance.advice(for: Self.standing(bottom: 1.0)) == .stepBack)
    }

    @Test func headTouchingTheTopMeansStepBack() {
        #expect(FramingGuidance.advice(for: Self.standing(top: 0.0)) == .stepBack)
    }

    @Test func tooFarAwayMeansStepCloser() {
        let far = Self.standing(top: 0.3, bottom: 0.7)
        #expect(FramingGuidance.advice(for: far) == .stepCloser)
        // Just far enough is fine.
        #expect(FramingGuidance.advice(for: Self.standing(top: 0.2, bottom: 0.8)) == .ready)
    }

    @Test func offToTheSideMeansMoveToTheMiddle() {
        #expect(FramingGuidance.advice(for: Self.standing(centerX: 0.75)) == .center)
        #expect(FramingGuidance.advice(for: Self.standing(centerX: 0.35)) == .ready)
    }

    @Test func morePeopleThanHerAreNotOk() {
        #expect(FramingGuidance.advice(for: Self.standing(people: 2)) == .moreThanOne)
    }

    // MARK: Facing the camera, arms, light

    @Test func facingAwayOrSidewaysMeansFaceTheCamera() {
        #expect(FramingGuidance.advice(for: Self.standing(faceFound: false)) == .faceTheCamera)
        // Side on, her shoulders almost overlap.
        #expect(FramingGuidance.advice(for: Self.standing(shoulderHalf: 0.02)) == .faceTheCamera)
    }

    @Test func armsAgainstHerBodyOrHandsOnHipsMeanArmsOut() {
        #expect(FramingGuidance.advice(for: Self.standing(armsOut: false)) == .armsOut)
        var onHips = Self.standing()
        onHips.joints[.leftWrist] = .init(x: 0.42, y: 0.5)
        #expect(FramingGuidance.advice(for: onHips) == .armsOut)
        var raised = Self.standing()
        raised.joints[.rightWrist] = .init(x: 0.7, y: 0.2)
        #expect(FramingGuidance.advice(for: raised) == .armsOut)
    }

    @Test func armsThatCantBeSeenAreNotComplainedAbout() {
        var hidden = Self.standing(armsOut: false)
        hidden.joints[.leftWrist] = nil
        hidden.joints[.rightWrist] = .init(x: 0.7, y: 0.58, confidence: 0.1)
        #expect(FramingGuidance.advice(for: hidden) == .ready)
    }

    @Test func darkMeansMoreLightAndLightBehindHerMeansTurn() {
        #expect(FramingGuidance.advice(for: Self.standing(frame: 0.15, subject: 0.1)) == .moreLight)
        #expect(FramingGuidance.advice(for: Self.standing(frame: 0.8, subject: 0.3)) == .backlit)
        // A bright frame with her well lit is fine.
        #expect(FramingGuidance.advice(for: Self.standing(frame: 0.8, subject: 0.7)) == .ready)
    }

    // MARK: Order and tips

    @Test func theMostUrgentThingComesFirst() {
        let messy = Self.standing(armsOut: false, anklesSeen: false, bottom: 0.9, frame: 0.1, subject: 0.1)
        #expect(
            FramingGuidance.issues(in: messy) == [.stepBack, .armsOut, .moreLight])
        #expect(FramingGuidance.advice(for: messy) == .stepBack)
    }
}

/// The coach that keeps the hints steady and times the photo.
struct FramingCoachTests {
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func aHintChangesOnlyAfterTwoFramesAgree() {
        var coach = FramingCoach()
        coach.observe(.stepBack, at: at(0))
        #expect(coach.advice == .starting)
        coach.observe(.stepBack, at: at(0.2))
        #expect(coach.advice == .stepBack)
        // One odd frame doesn't flip it.
        coach.observe(.armsOut, at: at(0.4))
        #expect(coach.advice == .stepBack)
        coach.observe(.stepBack, at: at(0.6))
        coach.observe(.armsOut, at: at(0.8))
        coach.observe(.armsOut, at: at(1.0))
        #expect(coach.advice == .armsOut)
    }

    @Test func goodFramingForASecondStartsTheCountdownThenTakesThePhotoOnce() {
        var coach = FramingCoach()
        coach.observe(.ready, at: at(0))
        coach.observe(.ready, at: at(0.2))  // ready, from 0.2
        let fired1 = coach.tick(at: at(0.9))
        #expect(!fired1)
        #expect(coach.countdown == nil)
        let fired2 = coach.tick(at: at(1.3))
        #expect(!fired2)
        #expect(coach.countdown == 3)
        let fired3 = coach.tick(at: at(2.4))
        #expect(!fired3)
        #expect(coach.countdown == 2)
        let fired4 = coach.tick(at: at(3.3))
        #expect(!fired4)
        #expect(coach.countdown == 1)
        let fired5 = coach.tick(at: at(4.3))
        #expect(fired5)
        #expect(coach.countdown == nil && coach.hasFired)
        // Once only.
        let fired6 = coach.tick(at: at(5))
        #expect(!fired6)
    }

    @Test func movingBeforeTheEndStopsTheCountdown() {
        var coach = FramingCoach()
        coach.observe(.ready, at: at(0))
        coach.observe(.ready, at: at(0.2))
        let fired7 = coach.tick(at: at(2.5))
        #expect(!fired7)
        #expect(coach.countdown == 2)
        coach.observe(.armsOut, at: at(2.6))
        coach.observe(.armsOut, at: at(2.8))
        #expect(coach.countdown == nil)
        let fired8 = coach.tick(at: at(6))
        #expect(!fired8)
        // Back in place: it starts again from the top.
        coach.observe(.ready, at: at(6.1))
        coach.observe(.ready, at: at(6.3))
        let fired9 = coach.tick(at: at(7.4))
        #expect(!fired9)
        #expect(coach.countdown == 3)
    }

    @Test func tappingTheShutterStopsTheTimerAndResetStartsOver() {
        var coach = FramingCoach()
        coach.observe(.ready, at: at(0))
        coach.observe(.ready, at: at(0.2))
        coach.markTaken()
        let fired10 = coach.tick(at: at(9))
        #expect(!fired10)
        coach.reset()
        #expect(coach.advice == .starting && !coach.hasFired)
    }

    @Test func anythingButReadyNeverTakesAPhoto() {
        var coach = FramingCoach()
        for step in 0..<40 { coach.observe(.stepBack, at: at(Double(step) * 0.2)) }
        let fired11 = coach.tick(at: at(30))
        #expect(!fired11)
    }
}
