import DesignSystem
import Models
import SwiftUI

/// The Today tab with a result (`results-versions.html`): the request line, the version switch
/// with the selected version's description, the bundle and its piece list, the four actions,
/// and Try a different outfit.
struct TodayResult: View {
    let model: YourLooksModel
    let text: YourLooksText
    let actions: YourLooksActions

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let result = model.result, let look = model.currentLook {
            let content = LookBundleContent(
                look: look, garments: model.garments, layoutSeed: model.originalLook?.id.rawValue)
            VStack(spacing: NookSpacing.medium) {
                if let problem = model.problem {
                    ProblemBanner(problem: problem, retry: actions.retry)
                }
                Text(text.requestLine)
                    .nookTextStyle(.note)
                    .foregroundStyle(.nook.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("results.request")
                if let partial = text.partialLine(missing: model.missing) {
                    NookBanner(
                        partial, systemImage: "info.circle",
                        actionTitle: model.request.source.isSuitcase
                            ? String(
                                localized: "Use Main closet", bundle: .module,
                                comment: "Partial result banner action: style from the whole closet")
                            : nil,
                        action: model.request.source.isSuitcase ? actions.useMainCloset : nil
                    )
                }
                versionSwitch(look: look)
                notes(result, look: look)
                LookBundle(
                    content, size: .large, title: YourLooksText.title(of: model.shownVersion), animatesEntrance: true
                )
                // A new result lays its pieces down again; switching versions doesn't.
                .id(result.id)
                .padding(.vertical, NookSpacing.small)
                LookPieceList(
                    content: content,
                    showsSameAsSimple: model.shownVersion != .simple,
                    changes: YourLooksText.changes(
                        in: look, simple: result.simple, original: model.originalLook, garments: model.garments),
                    onFindOne: actions.findOne
                )
                if model.canUndoChange {
                    changedLine
                }
                ResultActions(
                    isSaved: model.isSaved(look),
                    needsConnection: model.problem == .offline,
                    look: look,
                    actions: actions
                )
                tryDifferent
            }
        }
    }

    // MARK: Versions

    @ViewBuilder
    private func versionSwitch(look: Look) -> some View {
        let hasIdea = !look.ideas.isEmpty
        let description = YourLooksText.description(of: model.shownVersion, hasIdea: hasIdea)
        VStack(spacing: NookSpacing.small) {
            if model.versions.count > 1 {
                NookSegmentedPicker(
                    String(
                        localized: "Versions of this outfit", bundle: .module,
                        comment: "VoiceOver name of the Simple, Dressed up, Something new switch"),
                    selection: Binding(get: { model.shownVersion }, set: { model.version = $0 }),
                    options: model.versions.map { version in
                        .init(
                            version, title: YourLooksText.title(of: version),
                            hint: YourLooksText.description(
                                of: version, hasIdea: !(model.result?.look(for: version)?.ideas.isEmpty ?? true)),
                            identifier: "results.version.\(version.rawValue)")
                    }
                )
            }
            Text(description)
                .nookTextStyle(.note)
                .fontWeight(.semibold)
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("results.versionDescription")
        }
    }

    // MARK: Notes

    @ViewBuilder
    private func notes(_ result: StyleResult, look: Look) -> some View {
        let lines = result.notes.filter { note in
            // The suitcase note is about Something new, so it shows with that version.
            note != .noNewPieceInSuitcase || model.shownVersion == .somethingNew
        }
        .map { text.line(for: $0, now: model.request.createdAt, calendar: calendar) }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: NookSpacing.small) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.nook.accent)
                            .accessibilityHidden(true)
                        Text(line)
                            .foregroundStyle(.nook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .nookTextStyle(.note)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, NookSpacing.small)
        }
    }

    // MARK: Changed by her

    /// After a swap or a removal: says so, with Undo that lasts longer than the toast.
    private var changedLine: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NookSpacing.xSmall))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: NookSpacing.small))
        return layout {
            Text(YourLooksText.changedByHer)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            NookButton(
                YourLooksText.undo, systemImage: "arrow.uturn.backward", kind: .text, size: .small,
                action: actions.undoChange
            )
            .accessibilityHint(
                Text(
                    "Puts back the look as it was before your last change.", bundle: .module,
                    comment: "VoiceOver hint on Undo under a changed look")
            )
            .accessibilityIdentifier("results.undoChange")
        }
        .padding(.horizontal, NookSpacing.small)
    }

    // MARK: Try a different outfit

    private var tryDifferent: some View {
        let caption = String(
            localized: "Uses 1 styling request.", bundle: .module, comment: "Caption under the Style me button")
        return VStack(spacing: NookSpacing.xxSmall) {
            NookButton(
                String(localized: "Try a different outfit", bundle: .module, comment: "Your looks button (LR-05a)"),
                systemImage: "arrow.triangle.2.circlepath", kind: .text, action: actions.tryDifferentOutfit
            )
            .accessibilityHint(Text(caption))
            .accessibilityIdentifier("results.tryDifferent")
            Text(caption)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
        .padding(.top, NookSpacing.small)
    }
}

/// Save look, Try it on, Swap a piece and Ask stylist (RD-06): four equal buttons in two rows,
/// one column at the accessibility sizes (RD-06.3), with the fine print under them.
struct ResultActions: View {
    let isSaved: Bool
    /// Offline with a result on screen: Try it on and Ask stylist need a connection.
    let needsConnection: Bool
    let look: Look
    let actions: YourLooksActions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: NookSpacing.small) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: NookSpacing.small) {
                    save
                    tryOn
                    swap
                    ask
                }
            } else {
                Grid(horizontalSpacing: NookSpacing.small, verticalSpacing: NookSpacing.small) {
                    GridRow {
                        save
                        tryOn
                    }
                    GridRow {
                        swap
                        ask
                    }
                }
            }
            Text(
                needsConnection
                    ? String(
                        localized: "Try it on and Ask stylist need a connection. Save and Swap work offline.",
                        bundle: .module, comment: "Under the results buttons while offline")
                    : String(
                        localized: "Try-on pictures are simulated.", bundle: .module,
                        comment: "Fine print under the results buttons (RD-06)")
            )
            .nookTextStyle(.finePrint)
            .foregroundStyle(.nook.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, NookSpacing.small)
    }

    private var save: some View {
        NookButton(
            isSaved
                ? String(localized: "Saved", bundle: .module, comment: "Save look button once the look is saved")
                : String(localized: "Save look", bundle: .module, comment: "Results button (RD-06)"),
            systemImage: isSaved ? "heart.fill" : "heart",
            kind: isSaved ? .soft : .primary,
            fillsWidth: true
        ) { actions.toggleSave(look) }
        .accessibilityHint(
            isSaved
                ? Text("Takes it out of Saved Looks.", bundle: .module, comment: "VoiceOver hint on Saved")
                : Text("Keeps this version in Saved Looks.", bundle: .module, comment: "VoiceOver hint on Save look")
        )
        .accessibilityIdentifier("results.save")
    }

    private var tryOn: some View {
        NookButton(
            String(localized: "Try it on", bundle: .module, comment: "Results button (RD-06)"),
            systemImage: "camera", kind: .soft, fillsWidth: true
        ) { actions.tryOn(look) }
        .disabled(needsConnection)
        .accessibilityHint(
            Text(
                "Makes a simulated picture of this look.", bundle: .module, comment: "VoiceOver hint on Try it on")
        )
        .accessibilityIdentifier("results.tryOn")
    }

    private var swap: some View {
        NookButton(
            String(localized: "Swap a piece", bundle: .module, comment: "Results button (RD-06, LR-08)"),
            systemImage: "arrow.left.arrow.right", kind: .soft, fillsWidth: true
        ) { actions.swap(look) }
        .accessibilityIdentifier("results.swap")
    }

    private var ask: some View {
        NookButton(
            String(localized: "Ask stylist", bundle: .module, comment: "Results button (RD-06)"),
            systemImage: "bubble.left.and.bubble.right", kind: .soft, fillsWidth: true
        ) { actions.askStylist(look) }
        .disabled(needsConnection)
        .accessibilityIdentifier("results.askStylist")
    }
}

/// A failure while the earlier result stays on screen, such as Try a different outfit offline.
struct ProblemBanner: View {
    let problem: YourLooksModel.Failure
    let retry: () -> Void

    var body: some View {
        switch problem {
        case .offline:
            NookOfflineBanner(
                detail: String(
                    localized: "These looks are kept on this iPhone.", bundle: .module,
                    comment: "Offline banner over results"),
                retry: retry
            )
        case .stopped:
            EmptyView()
        case .notCompleted, .closetUnavailable, .requestChanged:
            NookBanner(
                String(
                    localized: "A different outfit didn’t come through. Nothing was charged.", bundle: .module,
                    comment: "Banner over results when Try a different outfit fails"),
                systemImage: "exclamationmark.circle",
                actionTitle: String(localized: "Try again", bundle: .module, comment: "Button on the Home banner"),
                action: retry
            )
        }
    }
}
