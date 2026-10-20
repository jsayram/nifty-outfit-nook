import DesignSystem
import Models
import SwiftUI

/// The four steps after the welcome. Each is an `OnboardingPage` around the step's own content.
struct OnboardingStepView: View {
    let step: OnboardingStep
    @Bindable var model: OnboardingModel

    var body: some View {
        switch step {
        case .name: OnboardingNameStep(model: model)
        case .privacy: OnboardingPrivacyStep(model: model)
        case .fit: OnboardingFitStep(model: model)
        case .closet: OnboardingClosetStep(model: model)
        }
    }
}

// MARK: - Name (RD-03)

/// Her name for the sign, with the sign on the wall showing it as she types. Optional: empty is
/// fine and the sign says Hello (RD-03.2). The rules are Profile's (`NameRules.signName`).
struct OnboardingNameStep: View {
    @Bindable var model: OnboardingModel
    @AccessibilityFocusState private var focus: NameFocus?

    private enum NameFocus: Hashable {
        case name
    }

    var body: some View {
        let problem = model.nameProblem
        OnboardingPage(
            step: .name, primaryTitle: OnboardingText.next, canContinue: problem == nil,
            actions: OnboardingPageActions(
                onContinue: { Task { await model.advance(from: .name) } },
                onSkip: { Task { await model.skip(.name) } })
        ) {
            sign(showing: problem == nil ? model.name : String(model.name.prefix(NameRules.signNameMaximum)))
        } content: {
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                EditorTextField(
                    label: OnboardingText.nameField, isOptional: true, prompt: OnboardingText.namePrompt,
                    text: $model.name, problem: problem.map(ProfileText.nameProblem),
                    identifier: "onboarding.name", focus: $focus, focusValue: .name)
                Text(OnboardingText.nameNote)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NookSpacing.xSmall)
            }
            .padding(NookSpacing.medium)
            .floorCard()
        }
    }

    /// The name sign from the room, as on Profile, with what she's typed on it.
    private func sign(showing name: String) -> some View {
        ZStack(alignment: .topLeading) {
            RoomArtImage(.nameSign)
            NameSignText(stored: name)
                .frame(width: ProfileHeader.signName.width, height: ProfileHeader.signName.height)
                .offset(x: ProfileHeader.signName.minX, y: ProfileHeader.signName.minY)
        }
        .frame(width: ProfileHeader.signSize.width, height: ProfileHeader.signSize.height)
    }
}

// MARK: - What the app does and where things stay

/// The privacy step, in plain words: what the app does, that everything stays on the phone, that
/// this test build sends nothing and asks for no permissions, that later features ask first, and
/// what the test build keeps when it closes. It asks for nothing.
struct OnboardingPrivacyStep: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingPage(
            step: .privacy, primaryTitle: OnboardingText.next,
            actions: OnboardingPageActions(onContinue: { Task { await model.advance(from: .privacy) } }),
            artStandsOnFloor: true
        ) {
            RoomArtImage(.drawersPrivacy)
                .frame(width: SettingsHeader.artSize.width * 0.8, height: SettingsHeader.artSize.height * 0.8)
                .offset(y: (SettingsHeader.artSize.height - SettingsHeader.feet + 2) * 0.8)
        } content: {
            SettingsGroup(identifier: "onboarding.privacy") {
                SettingsInfoRow(
                    title: OnboardingText.doesTitle, detail: OnboardingText.doesDetail, systemImage: "sparkles")
                SettingsInfoRow(
                    title: OnboardingText.staysTitle, detail: OnboardingText.staysDetail, systemImage: "lock")
                SettingsInfoRow(
                    title: OnboardingText.nothingSentTitle, detail: OnboardingText.nothingSentDetail,
                    systemImage: "wifi.slash")
                SettingsInfoRow(
                    title: OnboardingText.asksFirstTitle, detail: OnboardingText.asksFirstDetail,
                    systemImage: "hand.raised")
            }
            NookBanner(OnboardingText.whatsKept, systemImage: "info.circle", tone: .neutral)
                .accessibilityIdentifier("onboarding.kept")
        }
    }
}

// MARK: - Usual fit (LR-18)

/// Her usual fit, as on Fit and measurements: Fitted, Comfortable or Relaxed, none chosen to
/// start. Tapping the chosen one again clears it. Measurements aren't asked for here: they're
/// optional and Sensitive, and they live in Profile.
struct OnboardingFitStep: View {
    let model: OnboardingModel

    var body: some View {
        // Without the closet step (Release, Phase 20a) this is the last step, so it finishes.
        let isLast = model.steps.last == .fit
        OnboardingPage(
            step: .fit, primaryTitle: isLast ? OnboardingText.finish : OnboardingText.next,
            primaryImage: isLast ? "house" : "arrow.right", isWorking: isLast && model.isFinishing,
            problem: isLast && model.didFail ? OnboardingText.failed : nil,
            actions: OnboardingPageActions(
                onContinue: { Task { await model.advance(from: .fit) } },
                onSkip: { Task { await model.skip(.fit) } })
        ) {
            // A pair of trousers on a peg, as on Fit and measurements.
            VStack(spacing: -12) {
                RoomArtImage(.hallPeg)
                    .frame(width: 14, height: 14)
                    .zIndex(1)
                GarmentPicture(
                    photo: .noPhoto, category: .bottom, colors: [.navy], size: CGSize(width: 58, height: 84))
            }
        } content: {
            VStack(alignment: .leading, spacing: NookSpacing.small) {
                NookSectionHeader(OnboardingText.fitChoices)
                NookFlowLayout(spacing: NookSpacing.chipGap, lineSpacing: NookSpacing.xSmall) {
                    ForEach(Comfort.allCases, id: \.self) { fit in
                        NookChip(fit.title, isSelected: model.usualFit == fit) { model.toggle(fit) }
                            .accessibilityIdentifier("onboarding.fit.\(fit.rawValue)")
                    }
                }
                .padding(.horizontal, NookSpacing.medium)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(OnboardingText.fitChoices))
                SettingsNote(OnboardingText.fitNote)
            }
            .padding(.vertical, NookSpacing.xSmall)
            .floorCard()
        }
    }
}

// MARK: - Starting closet

/// The sample closet or an empty one, the sample chosen to start. The armoire on the wall fills
/// or empties with the choice. "Go to my room" finishes onboarding.
struct OnboardingClosetStep: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingPage(
            step: .closet, primaryTitle: OnboardingText.finish, primaryImage: "house", isWorking: model.isFinishing,
            problem: model.didFail ? OnboardingText.failed : nil,
            actions: OnboardingPageActions(onContinue: { Task { await model.advance(from: .closet) } }),
            artStandsOnFloor: true
        ) {
            ZStack {
                RoomArtImage(.closetArmoire)
                if model.startingCloset == .sample {
                    RoomArtImage(.closetArmoireClothes)
                }
            }
            .frame(width: ClosetHeader.armoireSize.width * 0.7, height: ClosetHeader.armoireSize.height * 0.7)
        } content: {
            VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                ForEach(StartingCloset.allCases, id: \.self) { closet in
                    StyleMeChoiceRow(
                        title: OnboardingText.title(closet), subtitle: OnboardingText.detail(closet),
                        systemImage: closet == .sample ? "hanger" : "square.dashed",
                        isSelected: model.startingCloset == closet, identifier: "onboarding.closet.\(closet.rawValue)"
                    ) {
                        model.startingCloset = closet
                    }
                }
                SettingsNote(OnboardingText.closetNote)
            }
            .padding(.vertical, NookSpacing.xSmall)
            .padding(.horizontal, NookSpacing.xSmall)
            .floorCard()
            .accessibilityElement(children: .contain)
        }
    }
}
