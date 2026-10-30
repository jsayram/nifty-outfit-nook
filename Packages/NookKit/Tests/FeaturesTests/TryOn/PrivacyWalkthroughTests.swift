import Foundation
import Models
import NookTestSupport
import Testing

@testable import Features

/// 33c: the privacy walkthrough tells the truth about what the app does: its beats are the real
/// steps in the real order, its words agree with the consent, and it plays, skips and ends as
/// the plan says.
@MainActor
struct PrivacyWalkthroughTests {
    // MARK: It matches what the app does

    @Test func everyRealStepHasABeatAndTheyComeInTheRealOrder() {
        let stages = WalkthroughBeat.allCases.compactMap(\.stage)
        // No step is missing, and none is shown before one that really comes first.
        #expect(Set(stages) == Set(TryOnStage.allCases))
        #expect(stages == stages.sorted())
        // Sending and coming back dressed are one real step (one request), so two beats share it.
        #expect(stages.filter { $0 == .dressing }.count == 2)
    }

    @Test func theFrameChangesFollowThePipeline() {
        let frames = WalkthroughBeat.allCases.map(\.frame)
        // Her face is covered before the backdrop, the backdrop before the check, the check before
        // anything is sent, and her face goes back on only after she comes back dressed.
        let veiled = WalkthroughBeat.veil.rawValue
        #expect(!WalkthroughBeat.yourPhoto.frame.veiled && frames[veiled].veiled)
        #expect(!frames[veiled].studio && WalkthroughBeat.backdrop.frame.studio)
        #expect(!WalkthroughBeat.backdrop.frame.checked && WalkthroughBeat.checked.frame.checked)
        #expect(WalkthroughBeat.sent.frame.inCloud && WalkthroughBeat.sent.frame.veiled)
        #expect(WalkthroughBeat.dressed.frame.dressed && !WalkthroughBeat.dressed.frame.inCloud)
        #expect(WalkthroughBeat.dressed.frame.veiled)
        let last = WalkthroughBeat.faceBack.frame
        #expect(!last.veiled && last.lock && last.dressed)
        // The face is never uncovered while anything is out of the phone.
        for beat in [WalkthroughBeat.sent, .dressed] { #expect(beat.frame.veiled) }
    }

    @Test func itTakesFiveToSixSeconds() {
        #expect((5.0...6.0).contains(WalkthroughBeat.totalSeconds))
    }

    @Test func itSaysTheSameThingAsTheConsent() {
        // The exact line from the plan, under the walkthrough and under See what was sent, with the
        // server's 30 minutes in the line itself (D13, 29 October 2026).
        #expect(
            TryOnConsentText.underPicture
                == "Your face never leaves your phone. A photo of your body, without your face and on a plain backdrop, and your clothing photos go to Black Forest Labs, who may keep them and use them to improve their models. On the way, our server holds them, encrypted, for up to 30 minutes while your picture is made, then deletes them."
        )
        // The consent and the line agree on the 30 minutes, word for word, so they never
        // contradict each other.
        #expect(TryOnConsentText.underPicture.hasSuffix(TryOnConsentText.whatGoes))
        // And nothing in the walkthrough says no one keeps the photos.
        let spoken = WalkthroughText.spoken.lowercased()
        for claim in ["nothing is kept", "never stored", "deleted right away", "keeps neither"] {
            #expect(!spoken.contains(claim))
        }
    }

    @Test func everyBeatHasItsOwnCaptionAndTheSpokenTextHasThemAll() {
        let captions = WalkthroughBeat.allCases.map(WalkthroughText.caption)
        #expect(Set(captions).count == captions.count && captions.allSatisfy { !$0.isEmpty })
        for caption in captions { #expect(WalkthroughText.spoken.contains(caption)) }
    }

    @Test func theLoadingCaptionsAreTheRealStepsInTheirOrder() {
        #expect(
            TryOnStage.allCases.map(TryOnStepText.caption) == [
                "Hiding your face", "Swapping in a studio backdrop", "Checking that no face is left",
                "Dressing you", "Putting you back together on your phone",
            ])
        // VoiceOver hears where each step is.
        #expect(TryOnStepText.rowLabel(.dressing, .stopped) == "Dressing you, stopped here")
        #expect(TryOnStepText.rowLabel(.hidingFace, .done) == "Hiding your face, done")
        #expect(TryOnStepText.rowLabel(.restoring, .todo) == "Putting you back together on your phone, not started")
    }

    @Test func theLoadingScreenSaysWhenNothingHasBeenSent() {
        for stage in [TryOnStage.hidingFace, .studioBackdrop, .checkingFace] {
            #expect(TryOnStepText.message(.preparing(stage)).contains("Nothing has been sent yet"))
        }
        // Once it is out, the message is the one that says what was sent.
        #expect(TryOnStepText.message(.preparing(.dressing)) == TryOnSheetText.sendingMessage)
    }

    // MARK: Reduce Motion

    @Test func reduceMotionFadesAndNeverMovesOrResizesTheFigure() {
        for beat in WalkthroughBeat.allCases {
            let calm = WalkthroughMotion(frame: beat.frame, reduceMotion: true)
            #expect(calm.figureScale == 1 && calm.figureLift == 0)
        }
        // While it is out with the image service the figure only fades, and comes back full.
        #expect(WalkthroughMotion(frame: WalkthroughBeat.sent.frame, reduceMotion: true).figureOpacity == 0.25)
        #expect(WalkthroughMotion(frame: WalkthroughBeat.dressed.frame, reduceMotion: true).figureOpacity == 1)
        // With motion on, it really shrinks and travels up to the cloud.
        let away = WalkthroughMotion(frame: WalkthroughBeat.sent.frame, reduceMotion: false)
        #expect(away.figureScale < 1 && away.figureLift < 0 && away.figureOpacity == 1)
        #expect(WalkthroughMotion(frame: WalkthroughBeat.faceBack.frame, reduceMotion: false).figureLift == 0)
    }

    // MARK: It plays

    @Test func itPlaysEveryBeatOnTheClockAndThenEnds() async {
        let clock = ManualClock()
        let model = PrivacyWalkthroughModel(canSkip: false, clock: clock)
        let playing = Task { await model.play() }
        var seen: [WalkthroughBeat] = []
        for beat in WalkthroughBeat.allCases {
            await clock.waitForSleepers(1)
            seen.append(model.beat)
            #expect(!model.isFinished)
            clock.advance(by: .seconds(beat.seconds))
        }
        let completed = await playing.value
        #expect(completed && model.isFinished)
        #expect(seen == WalkthroughBeat.allCases)
    }

    @Test func theFirstShowingCantBeSkipped() async {
        let clock = ManualClock()
        let model = PrivacyWalkthroughModel(canSkip: false, clock: clock)
        let playing = Task { await model.play() }
        await clock.waitForSleepers(1)
        model.skip()
        #expect(!model.isFinished)
        playing.cancel()
        _ = await playing.value
    }

    @Test func aReplayCanBeSkippedAtOnce() async {
        let clock = ManualClock()
        let model = PrivacyWalkthroughModel(canSkip: true, clock: clock)
        let playing = Task { await model.play() }
        await clock.waitForSleepers(1)
        model.skip()
        #expect(model.isFinished)
        // The screen hands over at once; the sleeping task ends when the view goes away.
        playing.cancel()
        let completed = await playing.value
        #expect(!completed)
    }

    @Test func leavingTheScreenStopsItWithoutCallingItWatched() async {
        let clock = ManualClock()
        let model = PrivacyWalkthroughModel(canSkip: false, clock: clock)
        let playing = Task { await model.play() }
        await clock.waitForSleepers(1)
        playing.cancel()
        let completed = await playing.value
        #expect(!completed && !model.isFinished)
    }
}
