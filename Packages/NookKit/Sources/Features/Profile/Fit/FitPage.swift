import DesignSystem
import Models
import SwiftUI

/// What Fit and measurements' controls do. The screen fills these in; snapshot tests leave them
/// empty.
struct FitActions {
    var retry: () -> Void = {}
    var chooseFit: (Comfort) -> Void = { _ in }
    var chooseUnits: (MeasurementUnits) -> Void = { _ in }
    var edit: (MeasurementField) -> Void = { _ in }
    var addPiece: () -> Void = {}
    var removePiece: (FitPiece) -> Void = { _ in }
}

/// Fit and measurements, top to bottom (`fit.html`, PRD §10.1, LR-13, LR-18):
///
/// 1. The title on the wall: everything is optional and stays on this iPhone.
/// 2. Usual fit: Fitted, Comfortable, Relaxed, with "Saved until you change it." (LR-18).
/// 3. Measurements, with in · lb or cm · kg: height, waist, hip, bust, inseam and weight. Each
///    row opens its sheet. Empty ones say "Not added"; nothing is guessed.
/// 4. Pieces that fit you well (LR-13), with Add a piece that fits you well, and the example line
///    only while there are none.
/// 5. The privacy line.
///
/// Everything here is Sensitive, so the page is covered in the app switcher.
struct FitPage: View {
    let model: ProfileModel
    var actions = FitActions()

    @Environment(\.closetIsStillImage) private var isStillImage
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The rows in `fit.html`'s order.
    static let fields: [MeasurementField] = [.height, .waist, .hips, .bust, .inseam, .weight]

    var body: some View {
        Group {
            if isStillImage {
                page
                    .background(Color.nook.floor)
            } else {
                TourScrollReader {
                    ScrollView(.vertical) {
                        page
                    }
                }
                .background(FloorBackground())
            }
        }
        .hiddenWhenInactive()
    }

    private var page: some View {
        VStack(spacing: 0) {
            header
            content
                .padding(.horizontal, NookSpacing.screenMargin)
                .padding(.top, NookSpacing.large)
                .padding(.bottom, NookSpacing.xxxLarge)
                .readablePane()
                .background(Color.nook.floor)
        }
    }

    /// The title and the line under it on the wall, with a pair of trousers hanging from a peg
    /// beside them (`fit.html`). The title wraps beside the drawing; at the accessibility sizes the
    /// drawing is left out so the title has the full width.
    private var header: some View {
        HStack(alignment: .top, spacing: NookSpacing.medium) {
            VStack(alignment: .leading, spacing: 6) {
                // "measurements" is too long a word for the display style at the accessibility
                // sizes, where it broke mid-word, so the title steps down one style there.
                Text(FitText.title)
                    .nookTextStyle(dynamicTypeSize.isAccessibilitySize ? .title : .display)
                    .foregroundStyle(.nook.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(FitText.lede)
                    .nookTextStyle(.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(.nook.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: -12) {
                    RoomArtImage(.hallPeg)
                        .frame(width: 14, height: 14)
                        .zIndex(1)
                    GarmentPicture(
                        photo: .noPhoto, category: .bottom, colors: [.navy], size: CGSize(width: 58, height: 84))
                }
                .padding(.top, NookSpacing.small)
                .accessibilityHidden(true)
            }
        }
        .padding(.leading, NookSpacing.xLarge)
        .padding(.trailing, NookSpacing.xLarge)
        .padding(.top, NookSpacing.small)
        .padding(.bottom, NookSpacing.xLarge)
        // The title and the trousers line up with the rows below on a wide window.
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

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            NookLoadingState(FitText.loading)
                .floorCard()
        case .failed:
            NookErrorState(FitText.failedTitle, message: FitText.failedMessage, retry: actions.retry)
                .floorCard()
        case .loaded:
            VStack(alignment: .leading, spacing: NookSpacing.groupGap) {
                usualFit
                measurements
                pieces
                privacy
            }
        }
    }

    // MARK: Usual fit (LR-18)

    private var usualFit: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            NookSectionHeader(FitText.usualFit)
            NookFlowLayout(spacing: NookSpacing.chipGap, lineSpacing: NookSpacing.xSmall) {
                ForEach(Comfort.allCases, id: \.self) { fit in
                    NookChip(fit.title, isSelected: model.profile.usualFit == fit) { actions.chooseFit(fit) }
                        .accessibilityIdentifier("fit.usual.\(fit.rawValue)")
                }
            }
            .padding(.horizontal, NookSpacing.medium)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(FitText.usualFit))
            .tourAnchor(FitTour.Anchor.usualFit, label: FitText.usualFit)
            note(FitText.usualFitNote, identifier: "fit.usualNote")
            note(FitText.usualFitComfortNote)
        }
        .padding(.vertical, NookSpacing.xSmall)
        .floorCard()
    }

    // MARK: Measurements

    private var measurements: some View {
        VStack(alignment: .leading, spacing: NookSpacing.xxSmall) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: NookSpacing.small) {
                    NookSectionHeader(FitText.measurements)
                    unitsPicker
                        .fixedSize()
                        .padding(.trailing, NookSpacing.small)
                        .padding(.top, NookSpacing.small)
                }
                VStack(alignment: .leading, spacing: NookSpacing.xSmall) {
                    NookSectionHeader(FitText.measurements)
                    unitsPicker
                        .padding(.horizontal, NookSpacing.small)
                }
            }
            ForEach(Self.fields, id: \.self) { field in
                measurementRow(field)
            }
        }
        .padding(NookSpacing.xSmall)
        .floorCard()
    }

    private var unitsPicker: some View {
        NookSegmentedPicker(
            FitText.units,
            selection: Binding(get: { model.units }, set: { actions.chooseUnits($0) }),
            options: MeasurementUnits.allCases.map { units in
                .init(
                    units, title: FitText.unitsTitle(units), hint: FitText.spokenUnits(units),
                    identifier: "fit.units.\(units.rawValue)")
            }
        )
        .tourAnchor(FitTour.Anchor.units, label: FitText.units)
    }

    private func measurementRow(_ field: MeasurementField) -> some View {
        let name = FitText.name(field)
        let shown = MeasurementFormat.shown(
            field, in: model.profile.measurements, units: model.units, locale: locale)
        return Button {
            actions.edit(field)
        } label: {
            NookRow(
                name, subtitle: field == .weight ? FitText.weightState : nil,
                value: shown?.text ?? FitText.notAdded, accessory: .chevron)
        }
        .buttonStyle(.nookRow)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(shown?.spoken ?? FitText.notAdded))
        .accessibilityHint(Text(shown == nil ? FitText.add(name) : FitText.edit(name)))
        .accessibilityIdentifier("fit.\(field.rawValue)")
        .tourAnchor(FitTour.Anchor.weight, label: name, isEnabled: field == .weight) { actions.edit(field) }
    }

    // MARK: Pieces that fit you well (LR-13)

    private var pieces: some View {
        VStack(alignment: .leading, spacing: NookSpacing.small) {
            NookSectionHeader(FitText.piecesSection)
            note(FitText.addPieceLine)
            if model.profile.fitPieces.isEmpty {
                note(FitText.addPieceExample, identifier: "fit.example")
            } else {
                VStack(spacing: NookSpacing.xxSmall) {
                    ForEach(model.profile.fitPieces) { piece in
                        pieceRow(piece)
                    }
                }
                note(FitText.piecesUse)
            }
            NookButton(FitText.addPiece, systemImage: "plus", kind: .pill, size: .small) {
                actions.addPiece()
            }
            .padding(.horizontal, NookSpacing.medium)
            .padding(.bottom, NookSpacing.small)
            .accessibilityIdentifier("fit.addPiece")
            .tourAnchor(FitTour.Anchor.addPiece, label: FitText.addPiece, action: actions.addPiece)
        }
        .padding(.vertical, NookSpacing.xSmall)
        .floorCard()
    }

    private func pieceRow(_ piece: FitPiece) -> some View {
        let line = Self.line(for: piece)
        return HStack(spacing: NookSpacing.xSmall) {
            NookRow(line, systemImage: "checkmark.seal")
            Button {
                actions.removePiece(piece)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.nook.textSecondary)
                    .frame(width: NookSpacing.minimumTapTarget, height: NookSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(FitText.remove(piece.brand)))
            .padding(.trailing, NookSpacing.xSmall)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fit.piece.\(piece.id.rawValue)")
    }

    /// "Example Denim Co. · Bottom · S · Fits well": brand, kind, size and fit in one line
    /// (LR-13.2).
    static func line(for piece: FitPiece) -> String {
        [piece.brand, piece.category.singularTitle, piece.sizeLabel, piece.result.title].joined(separator: " · ")
    }

    // MARK: Parts

    private var privacy: some View {
        Label {
            Text(FitText.privacy)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock")
                .accessibilityHidden(true)
        }
        .nookTextStyle(.note)
        .foregroundStyle(.nook.textSecondary)
        .padding(NookSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floorCard()
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String, identifier: String? = nil) -> some View {
        Text(text)
            .nookTextStyle(.note)
            .foregroundStyle(.nook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, NookSpacing.medium)
            .accessibilityIdentifier(identifier ?? "")
    }
}
