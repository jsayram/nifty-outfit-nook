import Testing

@testable import Features

/// Release blocker 11: the privacy step ships in Release, so it can't promise what the app no
/// longer keeps. Sign-in, the stylist, try-on and purchases send data, and each asks first.
struct OnboardingPrivacyTextTests {
    private var words: String {
        [
            OnboardingText.staysTitle, OnboardingText.staysDetail, OnboardingText.onlineTitle,
            OnboardingText.onlineDetail, OnboardingText.asksFirstTitle, OnboardingText.asksFirstDetail,
            OnboardingText.whatsKeptOnDevice,
        ].joined(separator: " ")
    }

    @Test func promisesNothingTheAppDoesNotKeep() {
        let oldClaims = [
            "all stays", "no account to make", "Nothing is sent", "sends nothing", "test build", "never for",
        ]
        for claim in oldClaims {
            #expect(!words.contains(claim), "\(claim)")
        }
    }

    @Test func namesWhatLeavesThePhone() {
        for feature in ["stylist", "Try-on", "Sign-in", "purchases"] {
            #expect(OnboardingText.onlineDetail.contains(feature), "\(feature)")
        }
    }

    @Test func sayingWhatIsSentComesBeforeSending() {
        #expect(OnboardingText.asksFirstDetail.contains("before anything goes"))
        for permission in ["camera", "location", "notifications"] {
            #expect(OnboardingText.asksFirstDetail.contains(permission), "\(permission)")
        }
    }
}
