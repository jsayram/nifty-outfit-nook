import Foundation
import Models
import Observation

/// The steps after the welcome, in order. The welcome is the flow's first screen, not a step.
enum OnboardingStep: Int, CaseIterable, Hashable, Sendable {
    /// The name on her sign (RD-03). Optional.
    case name
    /// What the app does and where her things are kept, in plain words, before any setup that
    /// matters (PRD §7, Onboarding).
    case privacy
    /// Her usual fit (LR-18). Optional.
    case fit
    /// The sample closet or an empty one. The last step.
    case closet

    /// "Step 1 of 4".
    var number: Int { rawValue + 1 }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }

    /// The steps she can skip. The privacy step only has Continue, and the closet step always has
    /// a choice made.
    var isOptional: Bool { self == .name || self == .fit }
}

/// Onboarding (Phase 17): the welcome, then her name for the sign, what the app does and where
/// her things stay, her usual fit, and the closet to start with. Every step but the last can be
/// left as it is, nothing asks for a permission, and nothing is saved until she finishes, when
/// `finish` hands the answers to the root (`AppRootModel`), which saves them and opens Home.
@MainActor
@Observable
final class OnboardingModel {
    /// The steps on screen after the welcome. Empty on the welcome.
    var path: [OnboardingStep] = []
    /// What she has typed for the sign, as typed.
    var name = ""
    var usualFit: Comfort?
    var startingCloset: StartingCloset = .sample
    /// True while the answers are being saved.
    private(set) var isFinishing = false
    /// The last try at finishing didn't work.
    private(set) var didFail = false

    /// Saves the answers and opens Home. Returns false when something wasn't saved.
    @ObservationIgnored private let finishing: @MainActor (OnboardingAnswers) async -> Bool

    init(
        name: String = "", usualFit: Comfort? = nil, startingCloset: StartingCloset = .sample,
        finish: @escaping @MainActor (OnboardingAnswers) async -> Bool = { _ in true }
    ) {
        self.name = name
        self.usualFit = usualFit
        self.startingCloset = startingCloset
        finishing = finish
    }

    /// The step on screen, or `nil` on the welcome.
    var step: OnboardingStep? { path.last }

    /// What's wrong with the name, if anything (`NameRules.signName`: one line, at most 20
    /// characters). Empty is fine: the sign says Hello.
    var nameProblem: NameProblem? {
        do {
            _ = try NameRules.signName(name)
            return nil
        } catch {
            return error
        }
    }

    /// Whether Continue works on `step`.
    func canContinue(_ step: OnboardingStep) -> Bool {
        step != .name || nameProblem == nil
    }

    /// The answers as they stand, with the name checked. A name that breaks the rules can't
    /// reach here: Continue is off while it does.
    var answers: OnboardingAnswers {
        OnboardingAnswers(
            signName: (try? NameRules.signName(name)) ?? "", usualFit: usualFit, startingCloset: startingCloset)
    }

    // MARK: Moving through

    /// Get started.
    func start() {
        didFail = false
        path = [.name]
    }

    /// Continue on `step`: the next step, or finishing on the last one.
    func advance(from step: OnboardingStep) async {
        guard canContinue(step) else { return }
        if let next = step.next {
            path.append(next)
        } else {
            await finish(answers)
        }
    }

    /// Skip for now: the step's answer goes back to nothing, then on as Continue does.
    func skip(_ step: OnboardingStep) async {
        switch step {
        case .name: name = ""
        case .fit: usualFit = nil
        case .privacy, .closet: break
        }
        await advance(from: step)
    }

    /// "I already use Nifty Outfit Nook": straight to Home with the sample closet.
    func skipSetup() async {
        await finish(.alreadyUsing)
    }

    /// Tapping a fit chip chooses it; tapping the chosen one clears it.
    func toggle(_ fit: Comfort) {
        usualFit = usualFit == fit ? nil : fit
    }

    private func finish(_ answers: OnboardingAnswers) async {
        guard !isFinishing else { return }
        isFinishing = true
        didFail = false
        let finished = await finishing(answers)
        isFinishing = false
        didFail = !finished
    }
}
