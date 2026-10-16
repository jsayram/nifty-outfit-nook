import Foundation
import Models
import Testing

/// Phase 17: what onboarding keeps, and how her answers reach the profile.
struct OnboardingTests {
    @Test func aFreshInstallHasNotFinished() {
        #expect(OnboardingState.fresh == OnboardingState(isCompleted: false, startingCloset: nil))
        #expect(!OnboardingState().isCompleted)
    }

    @Test func answersWriteTheNameAndTheFit() {
        var profile = Profile(signName: "Old", usualFit: .relaxed)
        OnboardingAnswers(signName: "Lily", usualFit: .fitted, startingCloset: .empty).apply(to: &profile)
        #expect(profile.signName == "Lily")
        #expect(profile.usualFit == .fitted)
    }

    @Test func aSkippedFitLeavesTheProfileOwn() {
        var profile = Profile(signName: "Old", usualFit: .relaxed)
        OnboardingAnswers(signName: "", usualFit: nil).apply(to: &profile)
        // An empty name is a choice: the sign says Hello (RD-03.2).
        #expect(profile.signName.isEmpty)
        #expect(profile.usualFit == .relaxed)
    }

    @Test func alreadyUsingAsksNothing() {
        let answers = OnboardingAnswers.alreadyUsing
        #expect(answers.signName.isEmpty)
        #expect(answers.usualFit == nil)
        #expect(answers.startingCloset == .sample)
    }

    @Test func nothingElseChangesInTheProfile() {
        var profile = Profile()
        profile.preferences.tracksLaundry = true
        profile.remembered.occasion = .dateNight
        let before = profile
        OnboardingAnswers(signName: "Lily", usualFit: .comfortable).apply(to: &profile)
        profile.signName = before.signName
        profile.usualFit = before.usualFit
        #expect(profile == before)
    }
}
