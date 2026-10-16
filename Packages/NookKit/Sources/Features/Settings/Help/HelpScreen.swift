import DesignSystem
import SwiftUI

/// Help (RD-10, `help.html`): the top desk drawer, also on Profile. Short answers bundled with
/// the app, so they work offline, each a topic she can open; the first is open to start. At the
/// end, "Still stuck?" opens Send feedback.
///
/// Help has no search: the mockup and PRD §22.3 ask for a short task list, and eight topics fit on
/// two screens. "What changed" (PRD §22.2, release notes) comes with the first public release.
struct HelpScreen: View {
    @State private var open: Set<HelpTopic.ID> = [HelpContent.topics[0].id]
    @State private var showsFeedback = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HelpPage(
            open: open,
            toggle: { id in
                withAnimation(reduceMotion ? nil : .snappy) {
                    if open.contains(id) { open.remove(id) } else { open.insert(id) }
                }
            },
            sendFeedback: { showsFeedback = true }
        )
        .navigationTitle(SettingsText.helpTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is on the wall, as on Profile.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "").accessibilityHidden(true)
            }
        }
        .navigationDestination(isPresented: $showsFeedback) {
            FeedbackScreen()
        }
        // Help's quick tour (Phase 16b).
        .screenTour(HelpTour.definition, isReady: !showsFeedback)
    }
}

/// Help, top to bottom. Separate from `HelpScreen` so snapshot tests can draw it.
struct HelpPage: View {
    let open: Set<HelpTopic.ID>
    var toggle: (HelpTopic.ID) -> Void = { _ in }
    var sendFeedback: () -> Void = {}
    var version = AppVersion.current

    var body: some View {
        SettingsPage(
            header: SettingsHeader(title: SettingsText.helpTitle, lede: SettingsText.helpLede, art: .drawersHelp)
        ) {
            ForEach(HelpTopic.Section.allCases, id: \.self) { section in
                SettingsGroup(header: HelpContent.title(section)) {
                    VStack(spacing: NookSpacing.xxSmall) {
                        ForEach(HelpContent.topics.filter { $0.section == section }) { topic in
                            HelpTopicView(topic: topic, isOpen: open.contains(topic.id)) {
                                toggle(topic.id)
                            }
                            // The tour points at the first question.
                            .tourAnchor(
                                HelpTour.Anchor.topic, label: topic.title,
                                isEnabled: topic.id == HelpContent.topics.first?.id
                            ) { toggle(topic.id) }
                        }
                    }
                }
            }
            stillStuck
            Text(SettingsText.versionLine(version))
                .nookTextStyle(.finePrint)
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, NookSpacing.xSmall)
                .floorCard()
        }
    }

    /// "Still stuck?" on a soft accent card: the way to Send feedback from here.
    private var stillStuck: some View {
        Button(action: sendFeedback) {
            NookRow(
                String(localized: "Still stuck?", bundle: .module, comment: "Help: the last card"),
                subtitle: String(
                    localized: "Send a private note to the developer.", bundle: .module,
                    comment: "Help: under Still stuck?"),
                systemImage: "bubble.left", iconFill: .nook.surface, accessory: .chevron)
        }
        .buttonStyle(.nookRow)
        .padding(.vertical, NookSpacing.xSmall)
        .background {
            NookRadius.shape(NookRadius.group)
                .fill(Color.nook.accentSoft)
                .softShadow(.drop, in: NookRadius.shape(NookRadius.group))
        }
        .accessibilityIdentifier("help.stillStuck")
        .tourAnchor(
            HelpTour.Anchor.stillStuck,
            label: String(localized: "Still stuck?", bundle: .module, comment: "Help: the last card"),
            action: sendFeedback)
    }
}

/// One topic: a row she taps to open or close, and its answer under it while it's open, on a
/// stronger tint with a soft shadow below (`details[open]` in `help.html`).
struct HelpTopicView: View {
    let topic: HelpTopic
    let isOpen: Bool
    let toggle: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The answer lines up with the topic's words, after the icon (`.ans` in `help.html`). At the
    /// accessibility sizes the icon sits above the words, so the answer starts at the edge too.
    private var answerIndent: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? NookSpacing.large : 56
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 0) {
                    NookRow(topic.title, systemImage: topic.systemImage)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.nook.chevron)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .padding(.trailing, NookSpacing.large)
                        .accessibilityHidden(true)
                }
                .contentShape(NookRadius.shape(NookRadius.group))
            }
            .buttonStyle(.nookRow)
            .accessibilityValue(
                isOpen
                    ? Text("Open", bundle: .module, comment: "VoiceOver: a Help topic shows its answer")
                    : Text("Closed", bundle: .module, comment: "VoiceOver: a Help topic hides its answer")
            )
            .accessibilityHint(
                isOpen
                    ? Text("Hides the answer.", bundle: .module, comment: "VoiceOver hint on an open Help topic")
                    : Text("Shows the answer.", bundle: .module, comment: "VoiceOver hint on a closed Help topic")
            )
            .accessibilityIdentifier("help.\(topic.id)")
            if isOpen {
                VStack(alignment: .leading, spacing: NookSpacing.small) {
                    Text(topic.answer)
                        .nookTextStyle(.body)
                        .foregroundStyle(.nook.textPrimary)
                    if let note = topic.note {
                        Text(note)
                            .nookTextStyle(.note)
                            .foregroundStyle(.nook.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, answerIndent)
                .padding(.trailing, NookSpacing.large)
                .padding(.bottom, NookSpacing.medium)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("help.\(topic.id).answer")
            }
        }
        .background {
            if isOpen {
                NookRadius.shape(NookRadius.group)
                    .fill(Color.nook.tintStrong)
                    .softShadow(.drop, in: NookRadius.shape(NookRadius.group))
            }
        }
    }
}
