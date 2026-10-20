import DesignSystem
import SwiftUI

/// One onboarding step, laid out like Profile and the settings screens: the title, "Step 1 of 4"
/// and a line on the wall with a small drawing beside them, the step's content on the floor, and
/// the buttons at the bottom.
///
/// The buttons stay at the bottom of the screen at the standard text sizes. At the accessibility
/// sizes they'd take half of it, so they follow the content instead and scroll with it. Snapshot
/// tests draw the whole page without the scroll view.
struct OnboardingPage<Art: View, Content: View>: View {
    let step: OnboardingStep
    let primaryTitle: String
    var primaryImage: String? = "arrow.right"
    var canContinue = true
    var isWorking = false
    /// Under the buttons when finishing didn't work.
    var problem: String?
    let actions: OnboardingPageActions
    /// True when the drawing stands on the floor line, like the chest or the armoire.
    var artStandsOnFloor = false
    @ViewBuilder let art: Art
    @ViewBuilder let content: Content

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var buttonsFollowContent: Bool { isStillImage || dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        if isStillImage {
            page
                .background(Color.nook.floor)
        } else {
            ScrollView(.vertical) {
                page
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(FloorBackground())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !buttonsFollowContent {
                    buttons
                        .padding(.top, NookSpacing.small)
                        .background(Color.nook.floor.ignoresSafeArea())
                }
            }
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: step, standsOnFloor: artStandsOnFloor) { art }
            VStack(alignment: .leading, spacing: NookSpacing.groupGap) {
                content
                if buttonsFollowContent {
                    buttons
                }
            }
            .padding(
                .horizontal, dynamicTypeSize.isAccessibilitySize ? NookSpacing.small : NookSpacing.screenMargin
            )
            .padding(.top, NookSpacing.large)
            .padding(.bottom, NookSpacing.xLarge)
            .readablePane()
            .background(Color.nook.floor)
        }
    }

    private var buttons: some View {
        VStack(spacing: NookSpacing.xxSmall) {
            NookButton(
                primaryTitle, systemImage: primaryImage, isLoading: isWorking, fillsWidth: true,
                action: actions.onContinue
            )
            .disabled(!canContinue)
            .accessibilityIdentifier("onboarding.continue")
            if let onSkip = actions.onSkip {
                NookButton(OnboardingText.skip, kind: .text, fillsWidth: true, action: onSkip)
                    .accessibilityIdentifier("onboarding.skip")
            }
            if let problem {
                FieldProblemNote(message: problem)
                    .accessibilityIdentifier("onboarding.problem")
            }
        }
        .padding(.horizontal, buttonsFollowContent ? 0 : NookSpacing.xLarge)
        .padding(.bottom, buttonsFollowContent ? 0 : NookSpacing.small)
        .frame(maxWidth: buttonsFollowContent ? .infinity : WindowLayout.readableWidth)
        .frame(maxWidth: .infinity)
    }
}

/// What a step's buttons do: Continue, and Skip for now on the optional steps.
struct OnboardingPageActions {
    let onContinue: () -> Void
    var onSkip: (() -> Void)?
}

/// The wall at the top of a step: its title, which step it is, a line under them, and a small
/// drawing on the right. At the accessibility sizes the drawing is left out and the title steps
/// down one style, so no word breaks mid-word (playbook, Phase 14a).
struct OnboardingHeader<Art: View>: View {
    let step: OnboardingStep
    var standsOnFloor = false
    @ViewBuilder let art: Art

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.onboardingStepCount) private var stepCount

    var body: some View {
        HStack(alignment: standsOnFloor ? .bottom : .center, spacing: NookSpacing.small) {
            VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                Text(OnboardingText.title(step))
                    .nookTextStyle(dynamicTypeSize.isAccessibilitySize ? .title : .display)
                    .foregroundStyle(.nook.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("onboarding.title")
                Text(OnboardingText.step(step.number, of: stepCount))
                    .nookTextStyle(.caption)
                    .foregroundStyle(.nook.textSecondary)
                    .accessibilityIdentifier("onboarding.stepCount")
                Text(OnboardingText.lede(step))
                    .nookTextStyle(.label)
                    .fontWeight(.regular)
                    .foregroundStyle(.nook.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, NookSpacing.small)
            .padding(.bottom, NookSpacing.xLarge)
            if !dynamicTypeSize.isAccessibilitySize {
                art
                    .padding(.bottom, standsOnFloor ? 0 : NookSpacing.large)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, NookSpacing.xLarge)
        .padding(.trailing, NookSpacing.medium)
        .readablePane()
        .background(Color.nook.wallGradient)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.nook.floorLine)
                .frame(height: 2)
                .offset(y: 2)
                .accessibilityHidden(true)
        }
    }
}

extension EnvironmentValues {
    /// How many steps onboarding has: four, or three in Release, which has no closet step
    /// (Phase 20a).
    @Entry var onboardingStepCount = OnboardingStep.allCases.count
}
