import DesignSystem
import Models
import SwiftUI

/// 33c: the words for the loading screen's steps. Each caption is one real step of the pipeline
/// (`TryOnStage`), and the list is drawn from where the picture really is (`TryOnProgress`), never
/// from a timer. Where a refusal or a failed job stopped, the list stops there.
enum TryOnStepText {
    static func caption(_ stage: TryOnStage) -> String {
        switch stage {
        case .hidingFace:
            String(localized: "Hiding your face", bundle: .module, comment: "Try-on step 1, on the phone (33c)")
        case .studioBackdrop:
            String(
                localized: "Swapping in a studio backdrop", bundle: .module,
                comment: "Try-on step 2, on the phone (33c)")
        case .checkingFace:
            String(
                localized: "Checking that no face is left", bundle: .module,
                comment: "Try-on step 3, on the phone: the check before anything is sent (33c)")
        case .dressing:
            String(localized: "Dressing you", bundle: .module, comment: "Try-on step 4, the image service (33c)")
        case .restoring:
            String(
                localized: "Putting you back together on your phone", bundle: .module,
                comment: "Try-on step 5, on the phone: her own head goes back on (33c)")
        }
    }

    /// The big line on the loading screen: the step in progress.
    static func headline(_ progress: TryOnProgress) -> String {
        if progress.isWaiting {
            return String(
                localized: "Waiting to start", bundle: .module, comment: "Try-on loading screen: an earlier job runs")
        }
        return caption(progress.stage)
    }

    /// One line under it: what is true right now, in plain words.
    static func message(_ progress: TryOnProgress) -> String {
        if progress.isWaiting {
            return String(
                localized: "Your other picture finishes first. Nothing has been sent yet.", bundle: .module,
                comment: "Try-on loading screen: waiting for an earlier job")
        }
        if progress.isStillGoing {
            return String(
                localized:
                    "Still dressing you. This one is taking a little longer. You can leave this screen: we’ll tell you when your picture is ready.",
                bundle: .module, comment: "Try-on loading screen: the job is taking longer")
        }
        switch progress.stage {
        case .hidingFace, .studioBackdrop, .checkingFace:
            return String(
                localized: "This happens on your iPhone. Nothing has been sent yet.", bundle: .module,
                comment: "Try-on loading screen: the phone's own steps")
        case .dressing:
            return TryOnSheetText.sendingMessage
        case .restoring:
            return String(
                localized: "Your picture is back. Your iPhone is putting your face back on.", bundle: .module,
                comment: "Try-on loading screen: the last step")
        }
    }

    static func rowLabel(_ stage: TryOnStage, _ mark: TryOnProgress.Mark) -> String {
        let caption = caption(stage)
        switch mark {
        case .done:
            return String(localized: "\(caption), done", bundle: .module, comment: "VoiceOver: a finished try-on step")
        case .doing:
            return String(
                localized: "\(caption), in progress", bundle: .module, comment: "VoiceOver: the try-on step running")
        case .waiting:
            return String(
                localized: "\(caption), waiting for your other picture", bundle: .module,
                comment: "VoiceOver: a try-on step that hasn't started")
        case .todo:
            return String(
                localized: "\(caption), not started", bundle: .module,
                comment: "VoiceOver: a try-on step still to come")
        case .stopped:
            return String(
                localized: "\(caption), stopped here", bundle: .module,
                comment: "VoiceOver: the try-on step that failed or was refused")
        }
    }

    static var listLabel: String {
        String(localized: "Steps", bundle: .module, comment: "VoiceOver: the try-on steps list")
    }

    static var watchHow: String {
        String(
            localized: "Watch how it works", bundle: .module,
            comment: "Try-on loading screen: plays the privacy walkthrough again (33c)")
    }

    static var watchHowHint: String {
        String(
            localized: "Shows how your photo is kept private while your picture is made.", bundle: .module,
            comment: "VoiceOver hint for Watch how it works (33c)")
    }
}

/// The steps in order, each marked done, in progress, waiting, not started or stopped. Reads as a
/// list: VoiceOver says each step with where it is, and Dynamic Type just wraps the captions.
struct TryOnStepsList: View {
    let progress: TryOnProgress

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            ForEach(TryOnStage.allCases, id: \.self) { stage in
                row(stage, progress.mark(for: stage))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(TryOnStepText.listLabel))
        .accessibilityIdentifier("tryOn.steps")
    }

    private func row(_ stage: TryOnStage, _ mark: TryOnProgress.Mark) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NookSpacing.small) {
            Image(systemName: symbol(mark))
                .foregroundStyle(tint(mark))
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            Text(TryOnStepText.caption(stage))
                .nookTextStyle(mark == .doing || mark == .stopped ? .label : .note)
                .foregroundStyle(mark == .todo ? Color.nook.textSecondary : Color.nook.textPrimary)
                .fontWeight(mark == .doing || mark == .stopped ? .semibold : .regular)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(TryOnStepText.rowLabel(stage, mark)))
        .accessibilityIdentifier("tryOn.step.\(stage)")
    }

    private func symbol(_ mark: TryOnProgress.Mark) -> String {
        switch mark {
        case .done: "checkmark.circle.fill"
        case .doing: "circle.dotted"
        case .waiting: "clock"
        case .todo: "circle"
        case .stopped: "exclamationmark.circle.fill"
        }
    }

    private func tint(_ mark: TryOnProgress.Mark) -> Color {
        switch mark {
        case .done: .nook.success
        case .doing: .nook.accent
        case .waiting, .todo: .nook.textSecondary
        case .stopped: .nook.error
        }
    }
}
