import Fixtures
import Foundation
import Models
import Testing

@testable import Features

/// Phase 17: moving through onboarding, what each step lets her do, and what finishing hands on.
@MainActor
struct OnboardingModelTests {
    /// Keeps what `finish` was given.
    @MainActor
    final class Finished {
        var answers: [OnboardingAnswers] = []
        var result = true
    }

    private func model(_ finished: Finished = Finished()) -> OnboardingModel {
        OnboardingModel { answers in
            finished.answers.append(answers)
            return finished.result
        }
    }

    @Test func theStepsComeInOrder() async {
        let finished = Finished()
        let model = model(finished)
        #expect(model.step == nil)
        model.start()
        #expect(model.path == [.name])
        await model.advance(from: .name)
        await model.advance(from: .privacy)
        await model.advance(from: .fit)
        #expect(model.path == [.name, .privacy, .fit, .closet])
        #expect(finished.answers.isEmpty)
        await model.advance(from: .closet)
        #expect(finished.answers == [OnboardingAnswers()])
    }

    @Test func stepNumbersAndSkips() {
        #expect(OnboardingStep.allCases.map(\.number) == [1, 2, 3, 4])
        #expect(OnboardingStep.allCases.filter(\.isOptional) == [.name, .fit])
        #expect(OnboardingStep.closet.next == nil)
        #expect(OnboardingText.step(2, of: 4) == "Step 2 of 4")
    }

    @Test func theNameFollowsTheSignRules() async {
        let model = model()
        model.start()
        model.name = "  Lily  "
        #expect(model.nameProblem == nil)
        #expect(model.answers.signName == "Lily")
        // Longer than 20 characters: Continue is off and nothing moves on.
        model.name = String(repeating: "a", count: 21)
        #expect(model.nameProblem == .tooLong(maximum: NameRules.signNameMaximum))
        #expect(!model.canContinue(.name))
        await model.advance(from: .name)
        #expect(model.path == [.name])
        // Empty is fine: the sign says Hello.
        model.name = ""
        #expect(model.canContinue(.name))
    }

    @Test func skippingForgetsTheStepAnswer() async {
        let finished = Finished()
        let model = model(finished)
        model.start()
        model.name = "Lily"
        await model.skip(.name)
        #expect(model.name.isEmpty)
        await model.advance(from: .privacy)
        model.toggle(.fitted)
        await model.skip(.fit)
        #expect(model.usualFit == nil)
        model.startingCloset = .empty
        await model.advance(from: .closet)
        #expect(finished.answers == [OnboardingAnswers(signName: "", usualFit: nil, startingCloset: .empty)])
    }

    @Test func tappingTheChosenFitClearsIt() {
        let model = model()
        model.toggle(.comfortable)
        #expect(model.usualFit == .comfortable)
        model.toggle(.relaxed)
        #expect(model.usualFit == .relaxed)
        model.toggle(.relaxed)
        #expect(model.usualFit == nil)
    }

    @Test func finishingHandsOnEveryAnswer() async {
        let finished = Finished()
        let model = model(finished)
        model.start()
        model.name = "Lily"
        await model.advance(from: .name)
        await model.advance(from: .privacy)
        model.toggle(.comfortable)
        await model.advance(from: .fit)
        await model.advance(from: .closet)
        #expect(
            finished.answers == [OnboardingAnswers(signName: "Lily", usualFit: .comfortable, startingCloset: .sample)])
        #expect(!model.didFail)
        #expect(!model.isFinishing)
    }

    @Test func aFailedFinishSaysSoAndCanBeTriedAgain() async {
        let finished = Finished()
        finished.result = false
        let model = model(finished)
        model.path = [.name, .privacy, .fit, .closet]
        await model.advance(from: .closet)
        #expect(model.didFail)
        #expect(model.path.last == .closet)
        finished.result = true
        await model.advance(from: .closet)
        #expect(!model.didFail)
        #expect(finished.answers.count == 2)
    }

    @Test func alreadyUsingGoesStraightToHome() async {
        let finished = Finished()
        let model = model(finished)
        model.name = "typed but not kept"
        await model.skipSetup()
        #expect(finished.answers == [.alreadyUsing])
    }

    @Test func theDebugFlag() {
        #expect(OnboardingLaunchOptions(launchArguments: []) == .standard)
        #expect(OnboardingLaunchOptions(launchArguments: ["-onboarding", "reset"]) == .reset)
        #expect(OnboardingLaunchOptions(launchArguments: ["-fixtures", "demo", "-onboarding", "skip"]) == .skip)
        #expect(OnboardingLaunchOptions(launchArguments: ["-onboarding", "later"]) == .standard)
        #expect(OnboardingLaunchOptions(launchArguments: ["-onboarding"]) == .standard)
    }
}
