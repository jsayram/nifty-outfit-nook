import Foundation
import Models

/// The words of onboarding (Phase 17). The welcome is `onboarding.html`'s; the steps after it have
/// no mockup and follow PRD §7 (Onboarding) and §5.1, in the plain voice of Profile and Privacy and
/// terms.
nonisolated enum OnboardingText {
    // MARK: Welcome (`onboarding.html`)

    static var welcomeTitle: String {
        String(localized: "Welcome home", bundle: .module, comment: "Onboarding: the welcome title")
    }

    static var welcomeLede: String {
        String(
            localized: "Style outfits from the clothes you already own.\nYour closet stays on this iPhone.",
            bundle: .module, comment: "Onboarding: under the welcome title, two lines")
    }

    static var getStarted: String {
        String(localized: "Get started", bundle: .module, comment: "Onboarding: the welcome's main button")
    }

    static var alreadyUsing: String {
        String(
            localized: "I already use Nifty Outfit Nook", bundle: .module,
            comment: "Onboarding: the welcome's text button, straight to Home")
    }

    static var alreadyUsingHint: String {
        String(
            localized: "Skips the setup and opens your room with the sample closet.", bundle: .module,
            comment: "VoiceOver hint on I already use Nifty Outfit Nook")
    }

    /// The hint in Release builds, which have no sample closet (Phase 20a).
    static var alreadyUsingEmptyHint: String {
        String(
            localized: "Skips the setup and opens your room.", bundle: .module,
            comment: "VoiceOver hint on I already use Nifty Outfit Nook, in a build with no sample closet")
    }

    static var deleted: String {
        String(
            localized: "Your data is deleted. The app is starting fresh.", bundle: .module,
            comment: "Toast on the welcome after Delete my data")
    }

    // MARK: Every step

    static func step(_ number: Int, of count: Int) -> String {
        String(
            localized: "Step \(number) of \(count)", bundle: .module,
            comment: "Onboarding: which step this is, under the title")
    }

    static var next: String {
        String(localized: "Continue", bundle: .module, comment: "Onboarding: goes to the next step")
    }

    static var skip: String {
        String(localized: "Skip for now", bundle: .module, comment: "Onboarding: skips an optional step")
    }

    static var failed: String {
        String(
            localized: "That didn’t work. Try again.", bundle: .module,
            comment: "Onboarding: finishing failed, under the button")
    }

    // MARK: Name

    static var nameTitle: String {
        String(localized: "Your name", bundle: .module, comment: "Onboarding: the name step's title")
    }

    static var nameLede: String {
        String(
            localized: "It goes on the little sign in your room.", bundle: .module,
            comment: "Onboarding: under the name step's title")
    }

    static var nameField: String {
        String(localized: "First name", bundle: .module, comment: "Onboarding: the name field's label")
    }

    static var namePrompt: String {
        String(localized: "Your first name", bundle: .module, comment: "Onboarding: the name field's placeholder")
    }

    static var nameNote: String {
        String(
            localized: "Leave it empty and the sign says Hello. You can change it later in Profile.",
            bundle: .module, comment: "Onboarding: under the name field")
    }

    // MARK: Privacy, in plain words

    static var privacyTitle: String {
        String(localized: "Your closet stays here", bundle: .module, comment: "Onboarding: the privacy step's title")
    }

    static var privacyLede: String {
        String(
            localized: "What the app does, and where your things are kept.", bundle: .module,
            comment: "Onboarding: under the privacy step's title")
    }

    static var doesTitle: String {
        String(
            localized: "Outfits from your own clothes", bundle: .module,
            comment: "Onboarding privacy: what the app does")
    }

    static var doesDetail: String {
        String(
            localized: "Add your pieces, then tap the laptop in your room. You’ll get one outfit in three versions.",
            bundle: .module, comment: "Onboarding privacy: what the app does, the line under it")
    }

    static var staysTitle: String {
        String(localized: "It all stays on this iPhone", bundle: .module, comment: "Onboarding privacy: row title")
    }

    static var staysDetail: String {
        String(
            localized: "Your pieces, looks, name and fit are kept here. There’s no account to make.",
            bundle: .module, comment: "Onboarding privacy: where things are kept")
    }

    static var nothingSentTitle: String {
        String(localized: "Nothing is sent", bundle: .module, comment: "Onboarding privacy: row title")
    }

    static var nothingSentDetail: String {
        String(
            localized:
                "This test build sends nothing. It doesn’t ask for your camera, photos, location or notifications.",
            bundle: .module, comment: "Onboarding privacy: nothing leaves the phone in Stage A")
    }

    static var asksFirstTitle: String {
        String(localized: "Later, it asks first", bundle: .module, comment: "Onboarding privacy: row title")
    }

    static var asksFirstDetail: String {
        String(
            localized:
                "When styling uses the internet, the app will say exactly what it sends and ask you before it sends anything.",
            bundle: .module, comment: "Onboarding privacy: consent later")
    }

    static var whatsKept: String {
        String(
            localized:
                "When this test build closes, it keeps your name and your Style Me settings in Profile, which closet you chose and which tips you’ve seen. It forgets the rest, like your fit and the pieces and looks you add.",
            bundle: .module, comment: "Onboarding privacy: what Stage A keeps across launches and what it forgets")
    }

    // MARK: Fit

    static var fitTitle: String {
        String(localized: "How you like clothes to fit", bundle: .module, comment: "Onboarding: the fit step's title")
    }

    static var fitLede: String {
        String(
            localized: "Optional. It helps Style Me choose pieces that feel right.", bundle: .module,
            comment: "Onboarding: under the fit step's title")
    }

    static var fitChoices: String {
        String(localized: "Usual fit", bundle: .module, comment: "Onboarding: VoiceOver name of the fit choices")
    }

    static var fitNote: String {
        String(
            localized:
                "How you like clothes to sit. You can change it in Profile, under Fit and measurements, and add measurements there if you want to.",
            bundle: .module, comment: "Onboarding: under the fit choices")
    }

    // MARK: Starting closet

    static var closetTitle: String {
        String(localized: "Choose a starting closet", bundle: .module, comment: "Onboarding: the last step's title")
    }

    static var closetLede: String {
        String(
            localized: "This test build can start with sample clothes, or with nothing.", bundle: .module,
            comment: "Onboarding: under the starting closet title")
    }

    static var sampleTitle: String {
        String(localized: "Sample closet", bundle: .module, comment: "Onboarding: starting closet choice")
    }

    static var sampleDetail: String {
        String(
            localized:
                "Example pieces, looks and suitcases, so you can try Style Me straight away. It comes back each time the app opens.",
            bundle: .module, comment: "Onboarding: what the sample closet is")
    }

    static var emptyTitle: String {
        String(localized: "Empty closet", bundle: .module, comment: "Onboarding: starting closet choice")
    }

    static var emptyDetail: String {
        String(
            localized:
                "Add your own pieces, with sample pictures for now. In this test build they’re gone when the app closes.",
            bundle: .module, comment: "Onboarding: what the empty closet is")
    }

    static var closetNote: String {
        String(
            localized: "To choose again later, use Delete my data in Profile.", bundle: .module,
            comment: "Onboarding: under the starting closet choices")
    }

    static var finish: String {
        String(localized: "Go to my room", bundle: .module, comment: "Onboarding: the last step's button")
    }

    // MARK: Words for each step

    static func title(_ step: OnboardingStep) -> String {
        switch step {
        case .name: nameTitle
        case .privacy: privacyTitle
        case .fit: fitTitle
        case .closet: closetTitle
        }
    }

    static func lede(_ step: OnboardingStep) -> String {
        switch step {
        case .name: nameLede
        case .privacy: privacyLede
        case .fit: fitLede
        case .closet: closetLede
        }
    }

    static func title(_ closet: StartingCloset) -> String {
        switch closet {
        case .sample: sampleTitle
        case .empty: emptyTitle
        }
    }

    static func detail(_ closet: StartingCloset) -> String {
        switch closet {
        case .sample: sampleDetail
        case .empty: emptyDetail
        }
    }
}
