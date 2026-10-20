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
    /// Restore from a backup file (Phase 21b), when the app has backups.
    @State private var backups: BackupsModel?
    @Environment(\.backupRestored) private var backupRestored

    init(
        notice: String?, offersSampleCloset: Bool = true, backups: (any BackupService)? = nil,
        finish: @escaping @MainActor (OnboardingAnswers) async -> Bool
    ) {
        self.notice = notice
        _model = State(initialValue: OnboardingModel(offersSampleCloset: offersSampleCloset, finish: finish))
        _backups = State(initialValue: backups.map { BackupsModel(service: $0) })
    }

    var body: some View {
        NavigationStack(path: $model.path) {
            WelcomeView(
                getStarted: model.start,
                alreadyUsing: { Task { await model.skipSetup() } },
                isWorking: model.isFinishing,
                problem: model.didFail ? OnboardingText.failed : nil,
                offersSampleCloset: model.offersSampleCloset,
                restore: backups.map { backups in { backups.pick(for: .restore) } }
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
        .modifier(OnboardingRestore(model: backups, restored: backupRestored))
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

/// Restore from a backup file on the welcome (Phase 21b, 0004 section 8): the Files picker, then
/// the restore sheet. When the restore is done, the root opens Home on the restored closet.
private struct OnboardingRestore: ViewModifier {
    let model: BackupsModel?
    let restored: BackupRestoredAction

    func body(content: Content) -> some View {
        if let model {
            @Bindable var model = model
            content
                .fileImporter(isPresented: $model.isPicking, allowedContentTypes: [.nookBackup]) { result in
                    model.picked(try? result.get())
                }
                .nookSheet(
                    item: $model.flow, title: { BackupFlowSheet.title($0) }, detents: [.large],
                    onDismiss: {
                        Task {
                            let reload = model.needsReload
                            await model.closed()
                            if reload { restored() }
                        }
                    }, content: { flow in BackupFlowSheet(model: model, flow: flow) }
                )
        } else {
            content
        }
    }
}
