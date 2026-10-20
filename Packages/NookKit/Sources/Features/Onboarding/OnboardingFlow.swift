import DesignSystem
import Models
import SwiftUI

/// Onboarding (Phase 17): the welcome, then four steps pushed one after another, each with Back
/// in the bar. The root (`AppRootView`) shows it on a fresh install and after Delete my data, and
/// hands the answers to `AppRootModel.finish`, which opens Home and its tour.
///
/// Nothing here asks for a permission (no camera, photos, location or notifications) or makes an
/// account.
struct OnboardingFlow: View {
    /// Said on the welcome as it opens: after Delete my data.
    let notice: String?

    @State private var model: OnboardingModel
    @State private var toast: NookToastMessage?

    init(
        notice: String?, offersSampleCloset: Bool = true,
        finish: @escaping @MainActor (OnboardingAnswers) async -> Bool
    ) {
        self.notice = notice
        _model = State(initialValue: OnboardingModel(offersSampleCloset: offersSampleCloset, finish: finish))
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            WelcomeView(
                getStarted: model.start,
                alreadyUsing: { Task { await model.skipSetup() } },
                isWorking: model.isFinishing,
                problem: model.didFail ? OnboardingText.failed : nil,
                offersSampleCloset: model.offersSampleCloset
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle(OnboardingText.welcomeTitle)
            .navigationDestination(for: OnboardingStep.self) { step in
                OnboardingStepView(step: step, model: model)
                    .navigationTitle(OnboardingText.title(step))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        // The title is on the wall, as on Profile; the bar keeps it for Back and
                        // VoiceOver.
                        ToolbarItem(placement: .principal) {
                            Text(verbatim: "").accessibilityHidden(true)
                        }
                    }
            }
        }
        .environment(\.onboardingStepCount, model.steps.count)
        .tint(.nook.accent)
        .nookToast($toast)
        .task {
            if let notice {
                toast = NookToastMessage(notice, systemImage: "checkmark")
            }
        }
    }
}
