import DesignSystem
import Models
import SwiftUI

/// Which small sheet a Style Me row opens (RD-02.2). Weather has its own, on its row.
nonisolated enum StyleMeSheet: String, Identifiable, Hashable, Sendable {
    case source
    case occasion
    case startingPiece
    case comfort
    case color
    case preferences

    var id: String { rawValue }
}

/// What the page asks its screen to do.
struct StyleMeActions {
    var retry: () -> Void = {}
    var open: (StyleMeSheet) -> Void = { _ in }
    var perform: (StyleMeNoticeAction) -> Void = { _ in }
    var styleMe: () -> Void = {}
}

/// The Style Me request (`styleme.html`, RD-02): one calm column with the request summary
/// (Source, Occasion, Starting piece), the options for this request (Weather, Comfort, Colour,
/// Preferences), and one Style me button. Each row shows its current value and opens its own
/// small sheet. Anything that stops or limits the request is said in words next to the row it's
/// about, with a way forward.
///
/// In a wide window (iPad, Phase 15b) the request sits on the left and the options with Style me
/// on the right, as the mockups' tablet layout has it (`WidePanes`).
struct StyleMePage: View {
    let model: StyleMeModel
    var actions = StyleMeActions()

    @Environment(\.locale) private var locale
    @Environment(\.closetIsStillImage) private var isStillImage

    var body: some View {
        Group {
            if isStillImage {
                content
            } else {
                TourScrollReader {
                    ScrollView { content }
                        .centersShortContentInWideWindows()
                }
            }
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: NookSpacing.groupGap) {
            switch model.phase {
            case .loading:
                NookLoadingState(
                    String(localized: "Getting Style Me ready", bundle: .module, comment: "Style Me while it loads")
                )
                .readablePane()
            case .failed:
                NookErrorState(
                    String(
                        localized: "Style Me didn’t load", bundle: .module, comment: "Style Me error state title"),
                    message: String(
                        localized: "Your closet couldn’t be read just now. Nothing was sent.", bundle: .module,
                        comment: "Style Me error state"),
                    retry: actions.retry
                )
                .readablePane()
            case .loaded:
                if model.check.issues.contains(.closetEmpty) {
                    closetEmpty
                        .readablePane()
                } else {
                    form(model.text(locale: locale))
                }
            }
        }
        .padding(.horizontal, NookSpacing.screenMargin)
        .padding(.top, NookSpacing.medium)
        .padding(.bottom, NookSpacing.xxxLarge)
        .frame(maxWidth: .infinity)
    }

    // MARK: Closet empty

    private var closetEmpty: some View {
        let notice = model.text(locale: locale).notice(for: .closetEmpty)
        return NookEmptyState(notice.title ?? "", message: notice.message, systemImage: "hanger") {
            NookButton(
                StyleMeNoticeAction.addPiece.title, systemImage: "plus", fillsWidth: true,
                action: { actions.perform(.addPiece) }
            )
            .accessibilityIdentifier("styleMe.notice.closetEmpty.addPiece")
        }
    }

    // MARK: The form

    private func form(_ text: StyleMeText) -> some View {
        WidePanes(
            spacing: NookSpacing.groupGap, alignment: .leading, verticalAlignment: .top,
            minimumWidth: WindowLayout.rowPanesMinimumWidth
        ) { _ in
            request(text)
        } trailing: { _ in
            options(text)
            styleMeButton(text)
        }
    }

    private func request(_ text: StyleMeText) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            NookSectionHeader(String(localized: "Your request", bundle: .module, comment: "Style Me section"))
            sourceCard(text)
            notices(text, for: .source)
            occasionCard(text)
            notices(text, for: .occasion)
            startingPieceCard(text)
            notices(text, for: .startingPiece)
        }
    }

    private func options(_ text: StyleMeText) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            NookSectionHeader(
                String(localized: "Options", bundle: .module, comment: "Style Me section"),
                detail: String(localized: "For this request only", bundle: .module, comment: "Style Me section detail")
            )
            WeatherRow(choice: weatherChoice, reading: model.weather)
            if let credit = model.weatherCredit, weatherChoice.wrappedValue == .useToday {
                WeatherCreditView(credit: credit)
                    .padding(.horizontal, NookSpacing.medium)
            }
            optionRow(
                .comfort, title: String(localized: "Comfort", bundle: .module, comment: "Style Me row"),
                line: text.comfortLine, value: text.comfortValue, systemImage: "tshirt",
                hint: String(
                    localized: "Choose today’s comfort.", bundle: .module, comment: "VoiceOver hint for Comfort"))
            optionRow(
                .color, title: String(localized: "Colour", bundle: .module, comment: "Style Me row"),
                line: nil, value: text.colorValue, systemImage: "paintpalette",
                hint: String(
                    localized: "Choose a colour for this look.", bundle: .module, comment: "VoiceOver hint for Colour"))
            optionRow(
                .preferences, title: String(localized: "Preferences", bundle: .module, comment: "Style Me row (LR-03)"),
                line: text.preferencesLine, value: text.preferencesValue, systemImage: "slider.horizontal.3",
                hint: String(
                    localized: "Choose whether looks may add a piece you don’t own.", bundle: .module,
                    comment: "VoiceOver hint for Preferences"))
            notices(text, for: .options)
        }
    }

    private var weatherChoice: Binding<WeatherChoice> {
        Binding(
            get: { model.draft.weatherChoice },
            set: { choice in model.update { $0.weatherChoice = choice } })
    }

    // MARK: Request cards

    private func sourceCard(_ text: StyleMeText) -> some View {
        RequestCard(
            caption: String(localized: "Source", bundle: .module, comment: "Style Me row caption"),
            value: text.sourceName,
            fill: .tint,
            open: { actions.open(.source) }
        ) {
            RequestCardIcon(systemImage: model.draft.source.isSuitcase ? "suitcase.rolling" : "door.left.hand.closed")
        } detail: {
            if model.draft.source.isSuitcase {
                NookBadge(
                    text.sourceDetail, systemImage: "lock", tone: model.check.piecesInSource == 0 ? .warning : .success)
            } else {
                Text(text.sourceDetail)
            }
        }
        .accessibilityLabel(Text(text.sourceLabel))
        .accessibilityHint(
            Text("Choose where your looks come from.", bundle: .module, comment: "VoiceOver hint for Source")
        )
        .accessibilityIdentifier("styleMe.source")
        .tourAnchor(StyleMeTour.Anchor.source, label: text.sourceLabel) { actions.open(.source) }
    }

    private func occasionCard(_ text: StyleMeText) -> some View {
        RequestCard(
            caption: String(localized: "Occasion", bundle: .module, comment: "Style Me row caption"),
            value: text.occasionValue,
            fill: .warning,
            open: { actions.open(.occasion) }
        ) {
            RequestCardIcon(systemImage: "calendar")
        } detail: {
            EmptyView()
        }
        .accessibilityLabel(
            Text("Occasion: \(text.occasionValue)", bundle: .module, comment: "VoiceOver label for Occasion")
        )
        .accessibilityHint(Text("Choose the occasion.", bundle: .module, comment: "VoiceOver hint for Occasion"))
        .accessibilityIdentifier("styleMe.occasion")
        .tourAnchor(
            StyleMeTour.Anchor.occasion,
            label: String(
                localized: "Occasion: \(text.occasionValue)", bundle: .module, comment: "VoiceOver label for Occasion")
        ) { actions.open(.occasion) }
    }

    private func startingPieceCard(_ text: StyleMeText) -> some View {
        RequestCard(
            caption: String(localized: "Starting piece", bundle: .module, comment: "Style Me row caption"),
            value: text.startingPieceValue,
            fill: .tint,
            open: { actions.open(.startingPiece) }
        ) {
            if let piece = model.startingPiece, text.startingPieceProblem == nil {
                GarmentPicture(piece, size: CGSize(width: 40, height: 40))
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            } else {
                RequestCardIcon(systemImage: "hanger")
            }
        } detail: {
            if let problem = text.startingPieceProblem {
                NookBadge(problem, systemImage: "exclamationmark.circle", tone: .warning)
            } else {
                Text(text.startingPieceDetail)
            }
        }
        .accessibilityLabel(
            Text(
                "Starting piece: \(text.startingPieceValue), \(text.startingPieceDetail)", bundle: .module,
                comment: "VoiceOver label for Starting piece: the piece and its line")
        )
        .accessibilityHint(
            Text("Choose a piece to build your looks around.", bundle: .module, comment: "VoiceOver hint")
        )
        .accessibilityIdentifier("styleMe.startingPiece")
    }

    // MARK: Options

    private func optionRow(
        _ sheet: StyleMeSheet, title: String, line: String?, value: String, systemImage: String, hint: String
    ) -> some View {
        Button {
            actions.open(sheet)
        } label: {
            NookRow(title, subtitle: line, value: value, systemImage: systemImage, accessory: .chevron)
        }
        .buttonStyle(.nookRow)
        .accessibilityHint(Text(hint))
        .accessibilityIdentifier("styleMe.\(sheet.rawValue)")
    }

    // MARK: Notices

    private enum NoticePlace {
        case source
        case occasion
        case startingPiece
        case options
    }

    private func place(of issue: StyleRequestIssue) -> NoticePlace {
        switch issue {
        case .closetEmpty, .suitcaseMissing, .suitcaseEmpty, .tooFewToStyle, .fewPieces: .source
        case .occasionNoteInvalid: .occasion
        case .startingPieceMissing, .startingPieceUnusable: .startingPiece
        case .requiredColorUnavailable: .options
        }
    }

    @ViewBuilder
    private func notices(_ text: StyleMeText, for place: NoticePlace) -> some View {
        ForEach(model.check.issues.filter { self.place(of: $0) == place }, id: \.self) { issue in
            NoticeCard(notice: text.notice(for: issue), blocks: issue.blocksStyling, perform: actions.perform)
        }
    }

    // MARK: Style me

    private func styleMeButton(_ text: StyleMeText) -> some View {
        VStack(spacing: NookSpacing.small) {
            NookButton(
                String(localized: "Style me", bundle: .module, comment: "The button that sends the Style Me request"),
                systemImage: "sparkles", fillsWidth: true, action: actions.styleMe
            )
            .disabled(!model.canStyle)
            .accessibilityHint(Text(text.buttonCaption))
            .accessibilityIdentifier("styleMe.go")
            .tourAnchor(
                StyleMeTour.Anchor.go,
                label: String(
                    localized: "Style me", bundle: .module, comment: "The button that sends the Style Me request")
            ) {
                // Only when the button itself could be tapped.
                if model.canStyle { actions.styleMe() }
            }
            Text(text.buttonCaption)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .padding(.top, NookSpacing.small)
    }
}

// MARK: - Parts

/// One line of the request summary (`.req`): an icon or the starting piece, a small caption,
/// the value in bold and a line under it, on a soft card with a chevron. No outline.
private struct RequestCard<Icon: View, Detail: View>: View {
    let caption: String
    let value: String
    let fill: NookCardFill
    let open: () -> Void
    @ViewBuilder let icon: Icon
    @ViewBuilder let detail: Detail

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: open) {
            let stacked = dynamicTypeSize.isAccessibilitySize
            HStack(alignment: stacked ? .top : .center, spacing: NookSpacing.medium) {
                if !stacked { icon }
                VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                    // At the accessibility sizes the icon sits above the words, as on Home's rows.
                    if stacked { icon }
                    Text(caption)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                    Text(value)
                        .nookTextStyle(.headline)
                        .foregroundStyle(.nook.textPrimary)
                    detail
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textSecondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.nook.chevron)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: NookSpacing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(RequestCardButtonStyle())
        .nookCard(fill, padding: NookSpacing.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }
}

private struct RequestCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The round icon on a request card.
private struct RequestCardIcon: View {
    let systemImage: String
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.nook.accent)
            .frame(width: size, height: size)
            .background(Color.nook.tintStrong, in: Circle())
            .accessibilityHidden(true)
    }
}

/// A note about something that stops or limits the request (`.stop` in the mockup): butter
/// when it stops Style me, a quiet tint when it's only a heads-up. Words and an icon, never
/// colour alone. Its actions move under the text, full width, at the large sizes.
private struct NoticeCard: View {
    let notice: StyleMeNotice
    let blocks: Bool
    let perform: (StyleMeNoticeAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: NookSpacing.small) {
                Image(systemName: blocks ? "exclamationmark.circle" : "info.circle")
                    .foregroundStyle(blocks ? Color.nook.warning : Color.nook.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
                    if let title = notice.title {
                        Text(title)
                            .nookTextStyle(.label)
                            .foregroundStyle(.nook.textPrimary)
                    }
                    Text(notice.message)
                        .nookTextStyle(.note)
                        .foregroundStyle(.nook.textPrimary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            // On the words, not the card: an identifier on the card's stack would rename its
            // buttons too (playbook, Phase 5a).
            .accessibilityIdentifier("styleMe.notice.\(notice.id)")
            if !notice.actions.isEmpty {
                NookFlowLayout(spacing: NookSpacing.small) {
                    ForEach(notice.actions, id: \.self) { action in
                        NookButton(action.title, systemImage: action.systemImage, kind: .pill, size: .small) {
                            perform(action)
                        }
                        .accessibilityIdentifier("styleMe.notice.\(notice.id).\(action.rawValue)")
                    }
                }
            }
        }
        .nookCard(blocks ? .warning : .tint, padding: NookSpacing.medium)
    }
}
