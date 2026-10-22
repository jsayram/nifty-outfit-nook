import DesignSystem
import Models
import SwiftUI

/// The Today tab with a result (`results-versions.html`): the request line, the version switch
/// with the selected version's description, the bundle and its piece list, the four actions,
/// and Try a different outfit.
///
/// In a wide window (iPad, Phase 15b) the version switch and the look sit on the left, larger,
/// with the notes, the pieces and the buttons beside them (`WidePanes`), as the mockups' tablet
/// layout has it. The order is the same, so VoiceOver reads it as on a phone.
struct TodayResult: View {
    let model: YourLooksModel
    let text: YourLooksText
    let actions: YourLooksActions

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The widest the look gets beside its pieces.
    static let wideBundleMaximumWidth: CGFloat = 420

    var body: some View {
        if let result = model.result, let look = model.currentLook {
            let content = LookBundleContent(
                look: look, garments: model.garments, layoutSeed: model.originalLook?.id.rawValue)
            VStack(spacing: NookSpacing.medium) {
                if let problem = model.problem {
                    ProblemBanner(problem: problem, retry: actions.retry)
                        .readablePane()
                }
                // Phase 28: looks made on the phone say so, and why.
                if let lane = result.madeBy, lane != .cloud {
                    QuickIdeasLabel(
                        lane: lane, reason: model.quickIdeasReason, retry: actions.retry,
                        reviewConsent: actions.reviewConsent
                    )
                    .readablePane()
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
                    .readablePane()
                }
                WidePanes(spacing: NookSpacing.medium) { isWide in
                    versionSwitch(look: look)
                    if !isWide {
                        notes(result, look: look)
                    }
                    bundle(content, result: result, isWide: isWide)
                    why(look)
                } trailing: { isWide in
                    if isWide {
                        notes(result, look: look)
                    }
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
                        needsConnection: model.problem == .offline || model.quickIdeasReason == .offline,
                        look: look,
                        actions: actions
                    )
                    tryDifferent
                }
            }
        }
    }

    /// The look, large; beside its pieces it grows to fill its pane, up to
    /// `wideBundleMaximumWidth`.
    @ViewBuilder
    private func bundle(_ content: LookBundleContent, result: StyleResult, isWide: Bool) -> some View {
        let title = YourLooksText.title(of: model.shownVersion)
        Group {
            if isWide {
                Color.clear
                    .aspectRatio(StickerBundleLayout.aspectRatio, contentMode: .fit)
                    .frame(maxWidth: Self.wideBundleMaximumWidth)
                    .overlay {
                        GeometryReader { proxy in
                            LookBundle(
                                content, size: LookBundleSize(width: proxy.size.width), title: title,
                                animatesEntrance: true)
                        }
                    }
            } else {
                LookBundle(content, size: .large, title: title, animatesEntrance: true)
            }
        }
        // A new result lays its pieces down again; switching versions doesn't.
        .id(result.id)
        .padding(.vertical, NookSpacing.small)
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
                // Beside the pieces on iPad it stays as wide as the look under it.
                .frame(maxWidth: Self.wideBundleMaximumWidth)
                .tourAnchor(
                    YourLooksTour.Anchor.versions,
                    label: String(
                        localized: "Versions of this outfit", bundle: .module,
                        comment: "VoiceOver name of the Simple, Dressed up, Something new switch"))
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

    // MARK: Why

    /// 27a: the stylist's one-line reason, under the look. Nothing when there isn't one.
    @ViewBuilder
    private func why(_ look: Look) -> some View {
        // Only while the look is as the stylist made it: after a swap the reason may not hold.
        if let original = model.originalLook, original.pieces == look.pieces, let why = original.why, !why.isEmpty {
            Text(why)
                .nookTextStyle(.body)
                .italic()
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, NookSpacing.medium)
                .accessibilityLabel(
                    Text("Why: \(why)", bundle: .module, comment: "VoiceOver: the stylist's reason for this look")
                )
                .accessibilityIdentifier("results.why")
        }
    }

    // MARK: Try a different outfit

    private var tryDifferent: some View {
        // Phase 28: Quick ideas on the phone cost nothing, so they don't say they do.
        let caption =
            model.nextRequestUsesStyling
            ? String(
                localized: "Uses 1 styling", bundle: .module,
                comment: "Caption under Try a different outfit: it costs one styling request (amendment, LR-05a)")
            : String(
                localized: "Made on this iPhone, free", bundle: .module,
                comment: "Caption under Try a different outfit when Quick ideas on the phone will answer")
        // FR-58: over a look from her history, the way on is New ideas.
        let title =
            model.isFromHistory
            ? String(localized: "New ideas", bundle: .module, comment: "Your looks button over a look from her history")
            : String(localized: "Try a different outfit", bundle: .module, comment: "Your looks button (LR-05a)")
        return VStack(spacing: NookSpacing.xxSmall) {
            NookButton(
                title,
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
/// one column at the accessibility sizes (RD-06.3), with the fine print under them. Every button
/// is the size of the largest, so a title that wraps makes all four taller together.
struct ResultActions: View {
    let isSaved: Bool
    /// Offline with a result on screen: Try it on and Ask stylist need a connection.
    let needsConnection: Bool
    let look: Look
    let actions: YourLooksActions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 33a: with real try-on pictures there's nothing simulated to say.
    @Environment(\.services) private var services

    var body: some View {
        VStack(spacing: NookSpacing.small) {
            EqualCellGrid(columns: dynamicTypeSize.isAccessibilitySize ? 1 : 2, spacing: NookSpacing.small) {
                save
                tryOn
                swap
                ask
            }
            if needsConnection || services.tryOnPipeline == nil {
                finePrint
            }
        }
        .padding(.top, NookSpacing.small)
    }

    private var finePrint: some View {
        Text(
            needsConnection
                ? String(
                    localized: "Try it on and Ask stylist need a connection. Save and Swap work offline.",
                    bundle: .module, comment: "Under the results buttons while offline")
                : SharedText.tryOnPicturesSimulated
        )
        .nookTextStyle(.finePrint)
        .foregroundStyle(.nook.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var save: some View {
        NookButton(
            isSaved
                ? String(localized: "Saved", bundle: .module, comment: "Save look button once the look is saved")
                : String(localized: "Save look", bundle: .module, comment: "Results button (RD-06)"),
            systemImage: isSaved ? "heart.fill" : "heart",
            kind: isSaved ? .soft : .primary,
            fillsWidth: true, fillsHeight: true
        ) { actions.toggleSave(look) }
        .accessibilityHint(
            isSaved
                ? Text("Takes it out of Saved Looks.", bundle: .module, comment: "VoiceOver hint on Saved")
                : Text("Keeps this version in Saved Looks.", bundle: .module, comment: "VoiceOver hint on Save look")
        )
        .accessibilityIdentifier("results.save")
        .tourAnchor(
            YourLooksTour.Anchor.save,
            label: isSaved
                ? String(localized: "Saved", bundle: .module, comment: "Save look button once the look is saved")
                : String(localized: "Save look", bundle: .module, comment: "Results button (RD-06)")
        ) { actions.toggleSave(look) }
    }

    private var tryOn: some View {
        NookButton(
            String(localized: "Try it on", bundle: .module, comment: "Results button (RD-06)"),
            systemImage: "camera", kind: .soft, fillsWidth: true, fillsHeight: true
        ) { actions.tryOn(look) }
        .disabled(needsConnection)
        .accessibilityHint(
            Text(
                "Makes a simulated picture of this look.", bundle: .module, comment: "VoiceOver hint on Try it on")
        )
        .accessibilityIdentifier("results.tryOn")
        .tourAnchor(
            YourLooksTour.Anchor.tryOn,
            label: String(localized: "Try it on", bundle: .module, comment: "Results button (RD-06)")
        ) {
            if !needsConnection { actions.tryOn(look) }
        }
    }

    private var swap: some View {
        NookButton(
            String(localized: "Swap a piece", bundle: .module, comment: "Results button (RD-06, LR-08)"),
            systemImage: "arrow.left.arrow.right", kind: .soft, fillsWidth: true, fillsHeight: true
        ) { actions.swap(look) }
        .accessibilityIdentifier("results.swap")
        .tourAnchor(
            YourLooksTour.Anchor.swap,
            label: String(localized: "Swap a piece", bundle: .module, comment: "Results button (RD-06, LR-08)")
        ) { actions.swap(look) }
    }

    private var ask: some View {
        NookButton(
            String(localized: "Ask stylist", bundle: .module, comment: "Results button (RD-06)"),
            systemImage: "bubble.left.and.bubble.right", kind: .soft, fillsWidth: true, fillsHeight: true
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
        case .needsConsent:
            NookBanner(StylistConsentText.needsConsent, systemImage: "hand.raised")
        case .limited(let problem):
            NookBanner(CloudLimitText.message(for: problem), systemImage: "hourglass")
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

/// Lays its views out in rows of `columns`, every cell as wide as the others and as tall as the
/// tallest view, so the results buttons are the same size at every text size (RD-06.3).
struct EqualCellGrid: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let cell = cellSize(proposal: proposal, subviews: subviews)
        let rows = rowCount(subviews.count)
        let width = cell.width * CGFloat(columnCount) + spacing * CGFloat(columnCount - 1)
        return CGSize(width: width, height: cell.height * CGFloat(rows) + spacing * CGFloat(max(rows - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = cellSize(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let column = index % columnCount
            let row = index / columnCount
            let origin = CGPoint(
                x: bounds.minX + CGFloat(column) * (cell.width + spacing),
                y: bounds.minY + CGFloat(row) * (cell.height + spacing))
            subview.place(at: origin, proposal: ProposedViewSize(cell))
        }
    }

    private var columnCount: Int { max(columns, 1) }

    private func rowCount(_ count: Int) -> Int {
        (count + columnCount - 1) / columnCount
    }

    /// One cell: an equal share of the width offered (or of the widest view's ideal width), and
    /// the height of the tallest view at that width.
    private func cellSize(proposal: ProposedViewSize, subviews: Subviews) -> CGSize {
        let gaps = spacing * CGFloat(columnCount - 1)
        let width =
            proposal.width.map { max(($0 - gaps) / CGFloat(columnCount), 0) }
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }
}
