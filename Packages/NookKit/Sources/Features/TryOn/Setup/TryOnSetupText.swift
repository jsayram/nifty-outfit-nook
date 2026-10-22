import Models
import SwiftUI

/// The words for the try-on photo's setup (Phase 33b): the guidance while she frames herself, the
/// check before she saves the photo, and what to do when it won't work. Plain and kind. Nothing
/// here mentions her hair: any hairstyle is fine, and the phone covers it.
nonisolated enum TryOnSetupText {
    // MARK: Live guidance

    static func guidance(_ advice: FramingAdvice) -> String {
        switch advice {
        case .starting:
            String(localized: "Getting ready to look for you", bundle: .module, comment: "Try-on camera hint")
        case .noOneInView:
            String(
                localized: "Your iPhone can’t see you yet. Step into the picture.", bundle: .module,
                comment: "Try-on camera hint"
            )
        case .moreThanOne:
            String(localized: "Just you in the picture, please.", bundle: .module, comment: "Try-on camera hint")
        case .stepBack:
            String(
                localized: "Step back a little, so your whole body is in view.", bundle: .module,
                comment: "Try-on camera hint")
        case .stepCloser:
            String(localized: "Step a little closer.", bundle: .module, comment: "Try-on camera hint")
        case .center:
            String(localized: "Move to the middle of the picture.", bundle: .module, comment: "Try-on camera hint")
        case .faceTheCamera:
            String(localized: "Turn to face the camera.", bundle: .module, comment: "Try-on camera hint")
        case .armsOut:
            String(
                localized: "Let your arms hang a little away from your body.", bundle: .module,
                comment: "Try-on camera hint")
        case .moreLight:
            String(localized: "A bit more light would help.", bundle: .module, comment: "Try-on camera hint")
        case .backlit:
            String(
                localized: "The light is behind you. Turn so it falls on you.", bundle: .module,
                comment: "Try-on camera hint")
        case .ready:
            String(localized: "That’s it. Hold still.", bundle: .module, comment: "Try-on camera hint")
        }
    }

    static func symbol(_ advice: FramingAdvice) -> String {
        switch advice {
        case .starting: "camera"
        case .noOneInView: "person.fill.questionmark"
        case .moreThanOne: "person.2"
        case .stepBack: "arrow.down.backward.and.arrow.up.forward"
        case .stepCloser: "arrow.up.forward.and.arrow.down.backward"
        case .center: "scope"
        case .faceTheCamera: "person.crop.circle"
        case .armsOut: "figure.arms.open"
        case .moreLight, .backlit: "sun.max"
        case .ready: "checkmark.circle.fill"
        }
    }

    static var guidanceOff: String {
        String(
            localized: "Live hints aren’t available right now. Tap the button when you’re ready.", bundle: .module,
            comment: "Try-on camera: Vision can't look at the camera")
    }

    static var takesItself: String {
        String(
            localized: "Take it for me when I’m ready", bundle: .module,
            comment: "Try-on camera: switch for the timer")
    }

    static var cameraTip: String {
        String(
            localized: "A plain wall and light on your face help. Arms a little away from your body.", bundle: .module,
            comment: "Try-on camera: a tip under the hint")
    }

    static var shutter: String {
        String(localized: "Take photo", bundle: .module, comment: "Try-on camera: the shutter button")
    }

    static var close: String {
        String(localized: "Close camera", bundle: .module, comment: "Try-on camera: closes it")
    }

    static var flip: String {
        String(localized: "Switch camera", bundle: .module, comment: "Try-on camera: front or back")
    }

    static var cameraDidNotStart: String {
        String(
            localized: "The camera didn’t start. You can close this and choose a photo instead.", bundle: .module,
            comment: "Try-on camera: it couldn't start")
    }

    static var photoFailed: String {
        String(
            localized: "The photo didn’t come out. Try again.", bundle: .module,
            comment: "Try-on camera: the shutter failed")
    }

    static func countdown(_ seconds: Int) -> String {
        String(
            localized: "Taking your photo in \(seconds)", bundle: .module,
            comment: "Try-on camera, spoken: the timer started. The argument is the seconds left")
    }

    // MARK: Before the camera

    static var cameraExplainerTitle: String {
        String(localized: "Take your try-on photo", bundle: .module, comment: "Before the camera permission prompt")
    }

    static var cameraExplainerMessage: String {
        String(
            localized:
                "The app uses your camera to take one full-length photo with a timer, and to see where you stand so it can tell you when it looks right. Nothing is recorded. The photo is kept on this iPhone, without its location, and in your iCloud if sync is on.",
            bundle: .module, comment: "Before the camera permission prompt: try-on photo (PERMISSIONS.md)")
    }

    // MARK: The sheet

    static var whatHelps: String {
        String(
            localized:
                "For the best pictures: stand where the camera sees you from head to toe, facing it, with your arms a little away from your body, in good light. A plain wall helps.",
            bundle: .module, comment: "Try-on photo sheet: what makes a good photo")
    }

    static var anyHair: String {
        String(
            localized:
                "Any hairstyle is fine. Hats, scarves and turtlenecks work too, but your picture looks best without them.",
            bundle: .module, comment: "Try-on photo sheet: hair, hats, scarves and turtlenecks")
    }

    static var hatsNote: String {
        String(
            localized: "Hats, scarves and turtlenecks are fine, but your picture looks best without them.",
            bundle: .module, comment: "Try-on photo setup: a gentle note after the check")
    }

    static var takePhoto: String {
        String(localized: "Take your photo", bundle: .module, comment: "Try-on photo sheet button")
    }

    static var takeNewPhoto: String {
        String(localized: "Take a new photo", bundle: .module, comment: "Try-on photo sheet button")
    }

    static var chooseFromPhotos: String {
        String(localized: "Choose from Photos", bundle: .module, comment: "Try-on photo sheet button")
    }

    static var chooseDifferent: String {
        String(localized: "Choose a different photo", bundle: .module, comment: "Try-on photo sheet button")
    }

    static var ownNote: String {
        String(
            localized:
                "The app only sees the photo you take or pick. It keeps its own copy on this iPhone, without the location, and nothing is uploaded.",
            bundle: .module, comment: "Try-on photo sheet: note with real photos")
    }

    // MARK: Checking

    static var checking: String {
        String(localized: "Checking your photo", bundle: .module, comment: "Try-on photo setup: working")
    }

    static var checkingNote: String {
        String(
            localized: "This happens on your iPhone. Nothing is sent.", bundle: .module,
            comment: "Try-on photo setup: working")
    }

    static var fineTitle: String {
        String(localized: "This photo works", bundle: .module, comment: "Try-on photo setup: the check passed")
    }

    static var fineMessage: String {
        String(
            localized:
                "Your iPhone can find you and cover your face before any picture is made. Nothing was sent.",
            bundle: .module, comment: "Try-on photo setup: the check passed")
    }

    static var tipsTitle: String {
        String(localized: "To make it even better", bundle: .module, comment: "Try-on photo setup: gentle tips")
    }

    static func tip(_ advice: FramingAdvice) -> String? {
        switch advice {
        case .stepBack:
            String(
                localized: "Your whole body may not be in the photo. Pictures look best from head to toe.",
                bundle: .module, comment: "Try-on photo setup: a gentle tip")
        case .stepCloser:
            String(
                localized: "You look a long way from the camera. Closer shows your clothes better.", bundle: .module,
                comment: "Try-on photo setup: a gentle tip")
        case .faceTheCamera:
            String(
                localized: "You may not be facing the camera. Facing it gives the best picture.", bundle: .module,
                comment: "Try-on photo setup: a gentle tip")
        case .armsOut:
            String(
                localized: "Your arms look close to your body. A little space between helps your clothes show.",
                bundle: .module, comment: "Try-on photo setup: a gentle tip")
        case .moreLight:
            String(
                localized: "The photo looks dark. Good light gives a cleaner picture.", bundle: .module,
                comment: "Try-on photo setup: a gentle tip")
        case .backlit:
            String(
                localized: "The light seems to be behind you. Light on you works better.", bundle: .module,
                comment: "Try-on photo setup: a gentle tip")
        default:
            nil
        }
    }

    static var useThisPhoto: String {
        String(localized: "Use this photo", bundle: .module, comment: "Try-on photo setup button")
    }

    static var keepAnyway: String {
        String(localized: "Keep it anyway", bundle: .module, comment: "Try-on photo setup button")
    }

    static var checkAgain: String {
        String(localized: "Check again", bundle: .module, comment: "Try-on photo setup button")
    }

    static var takeAnother: String {
        String(localized: "Take another photo", bundle: .module, comment: "Try-on photo setup button")
    }

    static var chooseAnother: String {
        String(localized: "Choose another photo", bundle: .module, comment: "Try-on photo setup button")
    }

    static var keepCurrent: String {
        String(localized: "Keep my current photo", bundle: .module, comment: "Try-on photo setup button")
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module, comment: "Try-on photo setup button")
    }

    static var notSaved: String {
        String(
            localized: "Your photo couldn’t be saved. Try again.", bundle: .module,
            comment: "Try-on photo setup: the photo couldn't be kept")
    }

    // MARK: A photo that won't work

    static func problemTitle(_ problem: TryOnPrepareProblem) -> String {
        switch problem {
        case .checksUnavailable, .notSaved, .photoUnreadable, .noTryOnPhoto, .noGarmentPhotos:
            String(
                localized: "Your iPhone couldn’t check this photo", bundle: .module,
                comment: "Try-on photo setup: the check didn't run")
        case .noPerson, .noFace, .severalPeople, .unclearOutline, .faceStillVisible:
            String(
                localized: "This photo won’t work for try-on", bundle: .module,
                comment: "Try-on photo setup: the check failed")
        }
    }

    static func problemMessage(_ problem: TryOnPrepareProblem) -> String {
        switch problem {
        case .noPerson:
            String(
                localized: "Your iPhone couldn’t find you in it. Try again with your whole body in view.",
                bundle: .module, comment: "Try-on photo setup: the check failed")
        case .noFace:
            String(
                localized: "Your iPhone couldn’t find your face. Face the camera, with your face clear and well lit.",
                bundle: .module, comment: "Try-on photo setup: the check failed")
        case .severalPeople:
            String(
                localized: "It seems to show more than one person. Try again with just you in the picture.",
                bundle: .module, comment: "Try-on photo setup: the check failed")
        case .unclearOutline:
            String(
                localized: "Your outline isn’t clear enough in it. Stand against a plain wall, in good light.",
                bundle: .module, comment: "Try-on photo setup: the check failed")
        case .faceStillVisible:
            String(
                localized:
                    "Your iPhone couldn’t be sure your face would stay hidden. Face the camera, with your face clear and well lit.",
                bundle: .module, comment: "Try-on photo setup: the check failed")
        case .checksUnavailable:
            String(
                localized:
                    "It didn’t work just now. You can check again, or keep the photo: it’s checked once more before any picture is made.",
                bundle: .module, comment: "Try-on photo setup: the check didn't run")
        case .photoUnreadable, .notSaved, .noTryOnPhoto, .noGarmentPhotos:
            String(
                localized: "This photo couldn’t be read. Try another one.", bundle: .module,
                comment: "Try-on photo setup: the photo couldn't be read")
        }
    }

    /// The footer under a photo that won't work: it can't make a picture, and nothing left the phone.
    static var problemFooter: String {
        String(
            localized:
                "Nothing was sent, and nothing has changed. Your current photo, if you have one, is still yours.",
            bundle: .module, comment: "Try-on photo setup: after a failed check")
    }
}
