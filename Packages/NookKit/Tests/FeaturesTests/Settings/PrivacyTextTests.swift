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

    /// N1: the other lines Jose left for later (9 November 2026). Help, Delete my data and the
    /// policies note ship in Release, so none of them may call this a test build.
    @Test func helpDeleteAndPoliciesPromiseNothingFalse() throws {
        let connection = try #require(HelpContent.topics.first { $0.id == "connection" })
        let words = [connection.answer, connection.note ?? "", DeleteDataText.nowhereElse, PrivacyText.policiesNote]
            .joined(separator: " ")
        for claim in ["test build", "no account", "sends nothing", "nothing you add is sent", "still being written"] {
            #expect(!words.contains(claim), "\(claim)")
        }
        #expect(DeleteDataText.nowhereElse.contains("Delete my account"))
    }

    /// Since D1 only a copy without her face leaves the phone, so the later try-on line says what
    /// the try-on switch says.
    @Test func tryOnLaterLineMatchesTheSwitch() throws {
        let tryOn = try #require(PrivacyText.later.first { $0.systemImage == "camera" })
        #expect(tryOn.detail == TryOnConsentText.switchDetail)
        #expect(tryOn.detail?.contains("without your face") == true)
    }
}
