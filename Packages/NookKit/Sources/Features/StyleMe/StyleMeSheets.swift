import DesignSystem
import Models
import SwiftUI

// The small sheets Style Me's rows open (RD-02.2, `styleme.html`). Each changes the draft
// straight away, so closing a sheet keeps every other choice. Single choices close the sheet;
// the Colour sheet and Other's words stay open until Close.

nonisolated extension StyleMeSheet {
    var title: String {
        switch self {
        case .source: String(localized: "Source", bundle: .module, comment: "Style Me sheet title")
        case .occasion: String(localized: "Occasion", bundle: .module, comment: "Style Me sheet title")
        case .startingPiece: String(localized: "Starting piece", bundle: .module, comment: "Style Me sheet title")
        case .comfort: String(localized: "Today’s comfort", bundle: .module, comment: "Style Me sheet title")
        case .color: String(localized: "Colour", bundle: .module, comment: "Style Me sheet title")
        case .preferences: String(localized: "Preferences", bundle: .module, comment: "Style Me sheet title (LR-03)")
        }
    }

    func subtitle(sourceName: String) -> String {
        switch self {
        case .source:
            String(localized: "Where your looks come from.", bundle: .module, comment: "Source sheet")
        case .occasion:
            String(localized: "Where are you going?", bundle: .module, comment: "Occasion sheet")
        case .startingPiece:
            String(
                localized: "Optional. Your looks are built around it. From \(sourceName) only.", bundle: .module,
                comment: "Starting piece sheet; the source's name")
        case .comfort:
            String(
                localized: "Just for this outfit. Your usual fit stays the same.", bundle: .module,
                comment: "Comfort sheet (LR-18)")
        case .color:
            String(localized: "Optional, for this request only.", bundle: .module, comment: "Colour sheet")
        case .preferences:
            String(
                localized: "How closely your looks stick to your own clothes.", bundle: .module,
                comment: "Preferences sheet (LR-03)")
        }
    }
}

/// One choice in a sheet: a row with a check mark when chosen, and the selected trait, so it
/// isn't shown by colour alone.
struct StyleMeChoiceRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NookSpacing.small) {
                NookRow(title, subtitle: subtitle, systemImage: systemImage)
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.nook.accent)
                    .opacity(isSelected ? 1 : 0)
                    .padding(.trailing, NookSpacing.medium)
                    .accessibilityHidden(true)
            }
            .background {
                if isSelected {
                    NookRadius.shape(NookRadius.group).fill(Color.nook.tint)
                }
            }
        }
        .buttonStyle(.nookRow)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Source

/// Main closet or one of her suitcases (FR-67). The choice is remembered for next time and shows
/// on Home's suitcase (Phase 13).
struct SourceChoices: View {
    let model: StyleMeModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
            row(.mainCloset, title: StyleMeText.mainCloset, systemImage: "door.left.hand.closed")
            if !model.activeSuitcases.isEmpty {
                NookSectionHeader(String(localized: "Suitcases", bundle: .module, comment: "Source sheet section"))
                ForEach(model.activeSuitcases) { suitcase in
                    row(.suitcase(suitcase.id), title: suitcase.name, systemImage: "suitcase.rolling")
                }
            }
        }
    }

    private func row(_ source: WardrobeSource, title: String, systemImage: String) -> some View {
        let count = model.pieceCount(in: source)
        var detail =
            count == 0
            ? String(localized: "Empty", bundle: .module, comment: "Source plate: the source has no pieces")
            : StyleMeText.pieces(count)
        if source.isSuitcase { detail += " · \(StyleMeText.suitcaseOnly)" }
        return StyleMeChoiceRow(
            title: title, subtitle: detail, systemImage: systemImage, isSelected: model.draft.source == source,
            identifier: "source.\(source.suitcaseID?.rawValue ?? "mainCloset")"
        ) {
            model.choose(source: source)
            close()
        }
    }
}

// MARK: - Occasion

/// The occasion chips (FR-03). Other asks for a few words, kept with this request only.
struct OccasionChoices: View {
    let model: StyleMeModel
    let close: () -> Void

    @Environment(\.closetIsStillImage) private var isStillImage
    @FocusState private var noteFocused: Bool

    /// In the order of FR-03.
    static let order: [Occasion] = [.office, .dateNight, .brunch, .concert, .casual, .event, .other]

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            NookChipBar(
                String(localized: "Occasion", bundle: .module, comment: "Name of the occasion chips"), layout: .wrap
            ) {
                ForEach(Self.order, id: \.self) { occasion in
                    NookChip(
                        occasion.title, systemImage: model.draft.occasion == occasion ? "checkmark" : nil,
                        isSelected: model.draft.occasion == occasion
                    ) {
                        model.update { $0.occasion = occasion }
                        if occasion == .other {
                            noteFocused = true
                        } else {
                            close()
                        }
                    }
                    .accessibilityIdentifier("occasion.\(occasion.rawValue)")
                }
            }
            .flushChipBar()
            if model.draft.occasion == .other {
                otherNote
            }
        }
    }

    private var note: Binding<String> {
        Binding(
            get: { model.draft.occasionNote },
            set: { text in
                // Stop at the limit as she types, rather than telling her off afterwards.
                model.update { $0.occasionNote = String(text.prefix(NameRules.occasionNoteMaximum)) }
            })
    }

    private var problem: String? {
        model.check.issues.lazy.compactMap { issue -> String? in
            if case .occasionNoteInvalid(let problem) = issue { return StyleMeText.occasionNoteProblem(problem) }
            return nil
        }.first
    }

    private var otherNote: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Text("What’s the occasion?", bundle: .module, comment: "Label for Other's words")
                .nookTextStyle(.label)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityHidden(true)
            Group {
                if isStillImage {
                    Text(model.draft.occasionNote.isEmpty ? Self.prompt : model.draft.occasionNote)
                        .foregroundStyle(
                            model.draft.occasionNote.isEmpty ? Color.nook.textSecondary : Color.nook.textPrimary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(Self.prompt, text: note, axis: .vertical)
                        .focused($noteFocused)
                        .submitLabel(.done)
                        .onSubmit(close)
                        .accessibilityLabel(
                            Text("What’s the occasion?", bundle: .module, comment: "Label for Other's words")
                        )
                        .accessibilityIdentifier("occasion.otherNote")
                }
            }
            .nookTextStyle(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, NookSpacing.small)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background {
                NookRadius.shape(NookRadius.button)
                    .fill(Color.nook.tintStrong)
                    .softShadow(.drop, in: NookRadius.shape(NookRadius.button))
            }
            Text(
                problem
                    ?? String(
                        localized: "Optional. Kept with this request only.", bundle: .module,
                        comment: "Under Other's words")
            )
            .nookTextStyle(.note)
            .foregroundStyle(problem == nil ? Color.nook.textSecondary : Color.nook.error)
            .fixedSize(horizontal: false, vertical: true)
            NookButton(
                String(localized: "Done", bundle: .module, comment: "Closes the Occasion sheet"), kind: .soft,
                size: .small, action: close
            )
            .accessibilityIdentifier("occasion.done")
        }
    }

    static var prompt: String {
        String(localized: "For example, museum visit", bundle: .module, comment: "Prompt for Other's words")
    }
}

// MARK: - Starting piece

/// "No starting piece", then the usable pieces in the source, searchable. Only pieces Style Me
/// may use today are offered, so a choice here never stops the request.
struct StartingPieceChoices: View {
    let model: StyleMeModel
    let sourceName: String
    let close: () -> Void

    @State private var query = ""
    @ScaledMetric(relativeTo: .footnote) private var tileWidth: CGFloat = 96
    @Environment(\.closetIsStillImage) private var isStillImage

    private var shown: [Garment] {
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return model.startingPieceChoices }
        return model.startingPieceChoices.filter { piece in
            let haystack =
                [piece.name, piece.category.singularTitle, piece.category.chipTitle]
                + piece.colors.map(\.title)
            return words.allSatisfy { word in haystack.contains { $0.localizedStandardContains(word) } }
        }
    }

    var body: some View {
        let choices = model.startingPieceChoices
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            StyleMeChoiceRow(
                title: StyleMeNoticeAction.clearStartingPiece.title, systemImage: "xmark",
                isSelected: model.draft.startingPieceID == nil, identifier: "startingPiece.none"
            ) {
                model.update { $0.startingPieceID = nil }
                close()
            }
            if choices.isEmpty {
                note(
                    String(
                        localized: "Nothing in \(sourceName) can be used today.", bundle: .module,
                        comment: "Starting piece sheet with no usable pieces; the source's name"))
            } else {
                NookSearchField(
                    String(
                        localized: "Search \(sourceName)", bundle: .module,
                        comment: "Starting piece sheet search; the source's name"),
                    text: $query)
                let pieces = shown
                if pieces.isEmpty {
                    note(
                        String(
                            localized: "Nothing in \(sourceName) matches “\(query)”.", bundle: .module,
                            comment: "Starting piece search with no match"))
                } else if isStillImage {
                    // A still image measures a lazy grid from estimates (Phase 20a).
                    StillAdaptiveGrid(minimum: tileWidth, spacing: NookSpacing.small, rowSpacing: NookSpacing.medium) {
                        ForEach(pieces) { piece in
                            tile(piece)
                        }
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: tileWidth), spacing: NookSpacing.small)],
                        spacing: NookSpacing.medium
                    ) {
                        ForEach(pieces) { piece in
                            tile(piece)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ piece: Garment) -> some View {
        let isSelected = model.draft.startingPieceID == piece.id
        return Button {
            model.update { $0.startingPieceID = piece.id }
            close()
        } label: {
            VStack(spacing: NookSpacing.xSmall) {
                GarmentPicture(piece, size: CGSize(width: 64, height: 72))
                    .frame(width: 64, height: 72)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.nook.accent, .nook.onAccent)
                        }
                    }
                Text(piece.name)
                    .nookTextStyle(.chip)
                    .foregroundStyle(isSelected ? Color.nook.accent : Color.nook.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(NookSpacing.small)
            .frame(maxWidth: .infinity, minHeight: NookSpacing.minimumTapTarget)
            .background {
                // The strong tint, not the soft accent: that one nearly vanishes on the wall
                // (playbook, Phase 4).
                if isSelected {
                    NookRadius.shape(NookRadius.group).fill(Color.nook.tintStrong)
                        .softShadow(.drop, in: NookRadius.shape(NookRadius.group))
                }
            }
            .contentShape(NookRadius.shape(NookRadius.group))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(piece.name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("startingPiece.\(piece.id.rawValue)")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .nookTextStyle(.body)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, NookSpacing.large)
    }
}

// MARK: - Comfort (LR-18)

/// Usual fit, or today's comfort for this request only.
struct ComfortChoices: View {
    let model: StyleMeModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            NookChipBar(
                String(localized: "Comfort", bundle: .module, comment: "Name of the comfort chips"), layout: .wrap
            ) {
                chip(nil, title: usualTitle, identifier: "comfort.usual")
                ForEach(Comfort.allCases, id: \.self) { comfort in
                    chip(comfort, title: comfort.title, identifier: "comfort.\(comfort.rawValue)")
                }
            }
            .flushChipBar()
            Text(
                "Your usual fit is set in Profile. Picking another one changes only this outfit.", bundle: .module,
                comment: "Comfort sheet note (LR-18)"
            )
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Usual fit (Relaxed)", or just "Usual fit" before she has set one.
    private var usualTitle: String {
        guard let usual = model.usualFit else {
            return String(
                localized: "Usual fit", bundle: .module, comment: "Style Me Comfort: her usual fit from Profile")
        }
        return String(
            localized: "Usual fit (\(usual.title))", bundle: .module, comment: "Comfort chip: her usual fit, named")
    }

    private func chip(_ comfort: Comfort?, title: String, identifier: String) -> some View {
        let isSelected = model.draft.comfort == comfort
        return NookChip(title, systemImage: isSelected ? "checkmark" : nil, isSelected: isSelected) {
            model.update { $0.comfort = comfort }
            close()
        }
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Colour (PRD §8.3)

/// A colour family, then how strongly and where. Strength and place wait until a colour is
/// picked.
struct ColorChoices: View {
    let model: StyleMeModel

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    var body: some View {
        let wish = model.draft.color
        VStack(alignment: .leading, spacing: NookSpacing.large) {
            NookChipBar(
                String(localized: "Colour", bundle: .module, comment: "Name of the colour swatches row"), layout: .wrap
            ) {
                NookChip(
                    String(localized: "Any", bundle: .module, comment: "Style Me Colour: no colour wish"),
                    systemImage: wish == nil ? "checkmark" : nil, isSelected: wish == nil
                ) {
                    model.update { $0.color = nil }
                }
                .accessibilityIdentifier("color.any")
                ForEach(ColorName.allCases, id: \.self) { family in
                    NookChip(family.title, swatch: swatch(family), isSelected: wish?.family == family) {
                        model.update { draft in
                            draft.color = ColorWish(
                                family, strength: draft.color?.strength ?? .preferred,
                                scope: draft.color?.scope ?? .anyPiece)
                        }
                    }
                    .accessibilityIdentifier("color.\(family.rawValue)")
                }
            }
            .flushChipBar()
            group(String(localized: "How strongly", bundle: .module, comment: "Colour sheet group")) {
                ForEach(ColorStrength.allCases, id: \.self) { strength in
                    NookChip(
                        strength.title, systemImage: wish?.strength == strength ? "checkmark" : nil,
                        isSelected: wish?.strength == strength
                    ) {
                        model.update { $0.color?.strength = strength }
                    }
                    .accessibilityIdentifier("color.strength.\(strength.rawValue)")
                }
            }
            group(String(localized: "Applies to", bundle: .module, comment: "Colour sheet group")) {
                ForEach(ColorScope.allCases, id: \.self) { scope in
                    NookChip(
                        scope.title, systemImage: wish?.scope == scope ? "checkmark" : nil,
                        isSelected: wish?.scope == scope
                    ) {
                        model.update { $0.color?.scope = scope }
                    }
                    .accessibilityIdentifier("color.scope.\(scope.rawValue)")
                }
            }
            Text(model.text(locale: locale).colorExplanation)
                .nookTextStyle(.note)
                .foregroundStyle(.nook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("color.explanation")
        }
    }

    private func group(_ title: String, @ViewBuilder chips: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Text(title)
                .nookTextStyle(.label)
                .foregroundStyle(.nook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            NookChipBar(title, layout: .wrap, content: chips)
                .flushChipBar()
                .disabled(model.draft.color == nil)
        }
    }

    private func swatch(_ color: ColorName) -> Color {
        // One dot can't show many colours; the stripes' first colour stands in, and the name says
        // the rest (as in Closet's filters).
        color == .multicolor
            ? GarmentColor.multicolorStripes[0].color(in: colorScheme)
            : GarmentColor.fill(for: color).color(in: colorScheme)
    }
}

// MARK: - Preferences (LR-03, LR-05b)

/// Exactly the two values, Mine + one idea and Only mine (LR-03.2). From a suitcase, every piece
/// comes from the suitcase whatever she picks, so the sheet says so and offers Main closet.
struct PreferencesChoices: View {
    let model: StyleMeModel
    let sourceName: String
    let close: () -> Void

    var body: some View {
        let fromSuitcase = model.draft.source.isSuitcase
        VStack(alignment: .leading, spacing: NookSpacing.medium) {
            if fromSuitcase {
                suitcaseNote
            }
            ForEach(PieceMode.allCases, id: \.self) { mode in
                StyleMeChoiceRow(
                    title: mode.title, subtitle: mode.detail,
                    systemImage: mode == .mineAndOneIdea ? "sparkles" : "hanger",
                    isSelected: model.draft.pieceMode == mode, identifier: "preferences.\(mode.rawValue)"
                ) {
                    model.update { $0.pieceMode = mode }
                    close()
                }
                .disabled(fromSuitcase)
                // Set by the source: dimmed, with the note above saying why. Never colour alone.
                .opacity(fromSuitcase ? 0.55 : 1)
            }
            Text(
                "It starts on your usual choice each time.", bundle: .module,
                comment: "Preferences sheet note: the choice is for this request"
            )
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var suitcaseNote: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Label {
                Text(StyleMeText.suitcaseOnly)
                    .nookTextStyle(.label)
            } icon: {
                Image(systemName: "lock")
            }
            .foregroundStyle(.nook.success)
            Text(
                "Only clothes packed in \(sourceName) are used, so Something new is another look from the suitcase. For a new-piece idea, style from Main closet.",
                bundle: .module, comment: "Preferences sheet when the source is a suitcase (LR-05b)"
            )
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            NookButton(
                String(localized: "Style from Main closet", bundle: .module, comment: "Preferences sheet button"),
                systemImage: "door.left.hand.closed", kind: .pill, size: .small
            ) {
                model.choose(source: .mainCloset)
            }
            .accessibilityIdentifier("preferences.mainCloset")
        }
        .padding(NookSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nook.successSurface, in: NookRadius.shape(NookRadius.group))
    }
}

extension View {
    /// A chip bar pads itself by the screen margin, for bars that run edge to edge. A sheet's
    /// content already has its margin, so this lines the chips up with the words above them.
    func flushChipBar() -> some View {
        padding(.horizontal, -NookSpacing.screenMargin)
    }
}
