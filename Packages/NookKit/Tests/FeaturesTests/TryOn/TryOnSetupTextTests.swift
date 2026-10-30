import Foundation
import Models
import Testing

@testable import Features

/// Phase 33b: the words for the try-on photo's setup, and the corrected consent text.
@MainActor
struct TryOnSetupTextTests {
    private static let problems: [TryOnPrepareProblem] = [
        .noTryOnPhoto, .photoUnreadable, .noPerson, .noFace, .severalPeople, .unclearOutline, .faceStillVisible,
        .checksUnavailable, .noGarmentPhotos, .notSaved,
    ]

    @Test func everyHintAndProblemHasKindWordsAndNeverAsksHerToChangeHerHair() {
        // Any hairstyle is fine (Jose, 19 October 2026): the phone covers the head and hair itself.
        var lines = FramingAdvice.allCases.map(TryOnSetupText.guidance)
        lines += FramingAdvice.allCases.compactMap(TryOnSetupText.tip)
        lines += Self.problems.flatMap { [TryOnSetupText.problemTitle($0), TryOnSetupText.problemMessage($0)] }
        lines += [TryOnSetupText.whatHelps, TryOnSetupText.hatsNote, TryOnSetupText.cameraTip]
        for line in lines {
            #expect(!line.isEmpty)
            #expect(!line.localizedCaseInsensitiveContains("hair"), "\(line)")
            #expect(!line.localizedCaseInsensitiveContains("ponytail"), "\(line)")
        }
    }

    @Test func onlyFramingProblemsGetATip() {
        let withTips: Set<FramingAdvice> = [.stepBack, .stepCloser, .faceTheCamera, .armsOut, .moreLight, .backlit]
        for advice in FramingAdvice.allCases {
            #expect((TryOnSetupText.tip(advice) != nil) == withTips.contains(advice))
        }
    }

    @Test func hatsScarvesAndTurtlenecksArePermittedButBetterWithout() {
        #expect(TryOnSetupText.hatsNote.contains("Hats, scarves and turtlenecks are fine"))
        #expect(TryOnSetupText.hatsNote.contains("best without them"))
        #expect(TryOnSetupText.anyHair.contains("Any hairstyle is fine"))
    }

    @Test func aPhotoThatWontWorkSaysNothingWasSent() {
        #expect(TryOnSetupText.problemFooter.contains("Nothing was sent"))
        #expect(TryOnSetupText.problemTitle(.noFace) == "This photo won’t work for try-on")
        #expect(TryOnSetupText.problemTitle(.checksUnavailable) == "Your iPhone couldn’t check this photo")
    }

    // MARK: The consent text (corrected 22 October 2026; the 30 minutes moved into the line, D13)

    @Test func theConsentSaysTheServerHoldsThePhotosEncryptedForUpTo30Minutes() {
        #expect(TryOnConsentText.whatGoes.contains("our server holds them, encrypted, for up to 30 minutes"))
        #expect(TryOnConsentText.whatGoes.hasSuffix("then deletes them."))
        // Said once: the paragraph after it no longer repeats it, and nothing says no one keeps them.
        let text = TryOnConsentText.comesBack
        #expect(!text.contains("30 minutes") && !text.contains("keeps neither"))
        #expect(text.contains("saved only on your iPhone"))
    }

    @Test func theApprovedDisclosureIsUntouched() {
        #expect(
            TryOnConsentText.whatGoes.hasPrefix(
                "A photo of your body, without your face and on a plain backdrop, and your clothing photos go to Black Forest Labs, who may keep them and use them to improve their models. "
            ))
    }
}
