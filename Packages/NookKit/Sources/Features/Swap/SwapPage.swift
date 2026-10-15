import DesignSystem
import Models
import SwiftUI

/// What Swap a piece asks its screen to do.
struct SwapActions {
    var use: () -> Void = {}
    var keep: () -> Void = {}
    var remove: () -> Void = {}
    var seeAll: () -> Void = {}
    var findOne: () -> Void = {}
}

/// Swap a piece (`swap.html`, LR-07, LR-08), top to bottom: which piece, the look with the
/// piece being changed lit and the rest stepped back, the line that says what the options are,
/// three of her pieces at a time, Show 3 more, the end of the list with See all and Find one,
/// then Keep current and Use this top, and Remove this piece.
///
/// One calm column on a phone. In a wide window (iPad, Phase 15b) the pieces and the look sit on
/// the left, larger, with the options and buttons beside them (`WidePanes`), as the mockups'
/// tablet layout has it. No outlines: options sit on soft tints and the chosen one gets a solid
/// name pill and the Selected trait.
struct SwapPage: View {
    let model: SwapModel
    var actions = SwapActions()

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    private var text: SwapText {
        SwapText(category: model.category, sourceName: model.setup.sourceName)
    }

    var body: some View {
        Group {
            if isStillImage {
                content
            } else {
                ScrollView { content }
            }
        }
        .background(Color.nook.wallGradient.ignoresSafeArea())
    }

    /// The look's width on a phone, and beside the options in a wide window.
    static let bundleWidth: CGFloat = 220
    static let wideBundleWidth: CGFloat = 320

    private var content: some View {
        WidePanes(spacing: NookSpacing.medium) { isWide in
            whichPiece
            preview(width: isWide ? Self.wideBundleWidth : Self.bundleWidth)
        } trailing: { _ in
            optionsSection
            commit
            removeSection
        }
        .padding(.horizontal, NookSpacing.screenMargin)
        .padding(.top, NookSpacing.small)
        .padding(.bottom, NookSpacing.xxxLarge)
        .frame(maxWidth: .infinity)
    }

    // MARK: Which piece

    private var whichPiece: some View {
        NookChipBar(
            String(localized: "Piece to swap", bundle: .module, comment: "Swap: VoiceOver name of the piece chips"),
            layout: .wrap
        ) {
            ForEach(model.pieces) { piece in
                let kind = model.category(of: piece).map(SwapText.pieceTitle) ?? ""
                NookChip(kind, isSelected: piece.id == model.pieceID) {
                    model.choosePiece(piece.id)
                }
                .accessibilityLabel(Text(verbatim: "\(kind), \(model.name(of: piece))"))
                .accessibilityIdentifier("swap.piece.\(model.category(of: piece)?.rawValue ?? "")")
            }
        }
    }

    // MARK: The look

    private func preview(width: CGFloat) -> some View {
        let look = model.shownLook
        let content = LookBundleContent(look: look, garments: model.setup.garments, layoutSeed: model.setup.layoutSeed)
        let focus = model.preview.map { "\(look.id)-\($0)" } ?? model.pieceID.rawValue
        let currentName = model.piece.map(model.name(of:)) ?? ""
        let tryingName = model.preview.flatMap { model.setup.garments[$0]?.name }
        return VStack(spacing: NookSpacing.xSmall) {
            LookBundle(
                content, size: LookBundleSize(width: width),
                title: String(localized: "The look", bundle: .module, comment: "Swap: spoken name of the look"),
                focusedPieceID: focus
            )
            .padding(.vertical, NookSpacing.xSmall)
            Text(SwapText.tagline(current: currentName, kind: model.category, previewing: tryingName))
                .nookTextStyle(.note)
                .fontWeight(.semibold)
                .foregroundStyle(.nook.accent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("swap.tagline")
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            Text(text.explanation)
                .nookTextStyle(.label)
                .foregroundStyle(.nook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("swap.explanation")
            if model.visibleOptions.isEmpty {
                quietLine(model.options.isEmpty ? text.nothingElse : text.noneThatGo)
                    .accessibilityIdentifier("swap.noOptions")
            } else {
                optionGrid
            }
            listEnd
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var optionGrid: some View {
        let columns =
            dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : Array(repeating: GridItem(.flexible(), spacing: NookSpacing.small, alignment: .top), count: 3)
        return LazyVGrid(columns: columns, spacing: NookSpacing.small) {
            ForEach(model.visibleOptions, id: \.self) { id in
                if let garment = model.setup.garments[id] {
                    SwapOption(garment: garment, isSelected: model.preview == id) {
                        model.select(id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var listEnd: some View {
        if model.canShowMore {
            NookButton(
                String(localized: "Show 3 more", bundle: .module, comment: "Swap: shows three more options (LR-07)"),
                systemImage: "plus", kind: .pill, size: .small
            ) {
                model.showMore()
            }
            .accessibilityHint(
                Text("Shows three more of your pieces. Nothing is sent.", bundle: .module, comment: "Swap hint")
            )
            .accessibilityIdentifier("swap.showMore")
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                if !model.visibleOptions.isEmpty {
                    quietLine(text.everyOne)
                        .accessibilityIdentifier("swap.everyOne")
                }
                if model.hasSeeAll {
                    NookButton(text.seeAll, systemImage: "square.grid.2x2", kind: .text, size: .small) {
                        actions.seeAll()
                    }
                    .accessibilityIdentifier("swap.seeAll")
                }
                if model.setup.allowsFindOne {
                    let layout =
                        dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                        : AnyLayout(HStackLayout(spacing: NookSpacing.xSmall))
                    layout {
                        Text(SwapText.findOneLead)
                            .nookTextStyle(.note)
                            .foregroundStyle(.nook.textSecondary)
                        NookButton(
                            String(
                                localized: "Find one", bundle: .module,
                                comment: "Button on a look's piece she doesn't own"),
                            systemImage: "magnifyingglass", kind: .text, size: .small, action: actions.findOne
                        )
                        .accessibilityIdentifier("swap.findOne")
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Keep or use

    private var commit: some View {
        VStack(spacing: NookSpacing.xSmall) {
            NookAdaptiveStack {
                NookButton(
                    String(localized: "Keep current", bundle: .module, comment: "Swap: leaves the look as it is"),
                    kind: .soft, fillsWidth: true, action: actions.keep
                )
                .accessibilityIdentifier("swap.keep")
                NookButton(text.use, fillsWidth: true, action: actions.use)
                    .disabled(model.preview == nil)
                    .accessibilityIdentifier("swap.use")
            }
            quietLine(text.hint(isPreviewing: model.preview != nil))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, NookSpacing.small)
    }

    // MARK: Remove

    private var removeSection: some View {
        VStack(spacing: NookSpacing.xxSmall) {
            NookButton(SwapText.remove, systemImage: "minus.circle", kind: .text, action: actions.remove)
                .disabled(model.removalProblem != nil)
                .accessibilityHint(model.removalProblem.map { Text(SwapText.whyNoRemove($0)) } ?? Text(""))
                .accessibilityIdentifier("swap.remove")
            if let problem = model.removalProblem {
                quietLine(SwapText.whyNoRemove(problem))
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func quietLine(_ line: String) -> some View {
        Text(line)
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One option: the piece as a sticker on a soft tint, its name under it. The chosen one gets a
/// solid accent name pill and the Selected trait, so the choice isn't shown by colour alone
/// (`.alt` in `swap.html`).
struct SwapOption: View {
    let garment: Garment
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            let layout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(HStackLayout(spacing: NookSpacing.medium))
                : AnyLayout(VStackLayout(spacing: NookSpacing.xSmall))
            layout {
                GarmentPicture(
                    garment, size: CGSize(width: 64, height: 72), presentation: .sticker(.centred)
                )
                .padding(NookSpacing.xSmall)
                .background(
                    isSelected ? Color.nook.tintStrong : Color.nook.tint, in: NookRadius.shape(NookRadius.tile)
                )
                Text(garment.name)
                    .nookTextStyle(.chip)
                    .foregroundStyle(isSelected ? Color.nook.onAccent : Color.nook.textPrimary)
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NookSpacing.small)
                    .padding(.vertical, NookSpacing.xxSmall)
                    .background(isSelected ? Color.nook.accent : Color.clear, in: Capsule())
                    .frame(
                        maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                        alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(garment.name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(
            Text("Shows it in the look.", bundle: .module, comment: "Swap: hint on an option")
        )
        .accessibilityIdentifier("swap.option.\(garment.id.rawValue)")
    }
}
