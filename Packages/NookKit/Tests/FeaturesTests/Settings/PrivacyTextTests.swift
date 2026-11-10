import Testing

@testable import Features

/// Privacy and terms ships in Release, so its top lines can't call this a test build or say
/// nothing is sent, the same claims as release blocker 11.
@MainActor
struct PrivacyTextTests {
    @Test func promisesNothingTheAppDoesNotKeep() {
        let words = [
            PrivacyText.summary, PrivacyText.summaryWithWeather, PrivacyText.laterNote,
            PrivacyTour.definition.steps[0].message,
        ].joined(separator: " ")
        for claim in ["test build", "no account", "sends nothing", "sent yet", "Nothing else is sent"] {
            #expect(!words.contains(claim), "\(claim)")
        }
    }

    @Test func saysWhereTheLocationGoesWhileLiveWeatherIsOn() {
        #expect(PrivacyText.summaryWithWeather.hasPrefix(PrivacyText.summary))
        #expect(PrivacyText.summaryWithWeather.contains("Apple Weather"))
    }

    /// With every feature in its own group there's nothing left to come, so the list goes.
    @Test func nothingIsListedForLaterOnceEveryFeatureHasItsGroup() {
        #expect(PrivacyText.later(includingWeather: false, includingStylist: false, includingTryOn: false).isEmpty)
    }
}
